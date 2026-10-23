import flash.geom.Matrix;
import flash.geom.Transform;
import org.flashNight.arki.scene.*;
import org.flashNight.gesh.depth.DepthManager;

/** Source29-frame transport art; existing WaveSpawnWheel owns all unit quantities. */
class org.flashNight.arki.scene.Cf6TransportService {
    private static function finite(value):Boolean {return typeof value=="number" && (value-value)==0 && Math.abs(value)<1000000;}
    private static function vector(values:Object,length:Number):Boolean {
        if(!(values instanceof Array) || values.length!=length) return false;
        for(var i:Number=0;i<length;i++) if(!finite(values[i])) return false;
        return true;
    }
    public static function validSpec(mapId:String,p:Object):Boolean {
        var depth:Number=mapId=="A09"?112:mapId=="A14"?505:mapId=="A18"?147:-1;
        return depth>0 && p.schema=="cf6-transport.v1" && p.id==mapId+"-transport-"+depth
            && p.sourceSprite===1868 && p.frames===29 && p.dispatchFrame===29 && p.subWaveIndex===1
            && p.url=="flashswf/backgrounds/cf6/preparation/CF6_Transport1868.swf"
            && finite(p.x) && finite(p.y) && finite(p.sortY) && vector(p.artMatrix,6) && vector(p.hitBounds,4)
            && Math.abs(p.artMatrix[0]*p.artMatrix[3]-p.artMatrix[1]*p.artMatrix[2])>0.000001
            && p.hitBounds[0]<p.hitBounds[2] && p.hitBounds[1]<p.hitBounds[3];
    }
    public static function current(s:Object):Boolean {
        var r:Object=s.room;
        return s!=null && !s.closed && !s.failed && r.transportSession===s && r.world===_root.gameworld
            && r.owner===r.world.__stageReturnWorldIdentity && r.world.__cf6Mechanism===r && !r.failed
            && r.stageManager===StageManager.instance && r.stageIndex===r.stageManager.currentStage
            && r.stageManager.isActive===true && r.stageManager.isFailed!==true && r.stageManager.isFinished!==true
            && r.slot===String(_root.savePath) && r.stageName===_root.当前关卡名
            && BookRunRules.sameCf6Run(r.runIdentity,_root._saveExt.bookRun);
    }
    private static function owns(s:Object):Boolean {
        return current(s) && Cf6PropDepthService.valid(s.ticket)
            && s.ticket.holder.__cf6TransportOwner===s.token;
    }
    public static function begin(room:Object,p:Object):Object {
        if(!validSpec(room.mapId,p) || room.transportSession!=null && !room.transportSession.closed) return null;
        var spec:Object={id:p.id,url:p.url,x:p.x,y:p.y,sortY:p.sortY,frames:29,dispatchFrame:29,subWaveIndex:1,
            artMatrix:p.artMatrix.concat(),hitBounds:p.hitBounds.concat()};
        var s:Object={room:room,spec:spec,spawner:WaveSpawner.instance,token:{},phase:"loading",frame:1,age:0,
            closed:false,failed:false,attempted:false,ready:false};
        room.transportSession=s;
        if(!current(s) || typeof room.world.dispatcher.publish!="function") {s.closed=true;return null;}
        var depth:Object=Cf6PropDepthService.begin(room.world,room.owner,room);
        if(depth==null) {s.closed=true;return null;}
        room.propDepth=depth;s.ticket=Cf6PropDepthService.create(depth,spec.id,spec.x,spec.y,spec.sortY);
        if(s.ticket==null) {s.closed=true;return null;}
        s.ticket.holder.__cf6TransportOwner=s.token;
        s.art=s.ticket.holder.createEmptyMovieClip("art",0);
        s.loader=new MovieClipLoader();s.listener={
            onLoadInit:function(mc:MovieClip):Void {Cf6TransportService.loaded(s,mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {if(Cf6TransportService.current(s)) Cf6TransportService.fail(s,"load:"+error);}};
        s.loader.addListener(s.listener);
        if(!s.loader.loadClip(spec.url,s.art)) fail(s,"load-request");
        return s;
    }
    public static function loaded(s:Object,art:MovieClip):Void {
        if(!owns(s) || s.ready || art!==s.ticket.holder.art || art._parent!==s.ticket.holder) return;
        s.loader.removeListener(s.listener);
        if(art._totalframes!==29) {fail(s,"native-frame-count");return;}
        s.art=art;var m:Array=s.spec.artMatrix;
        var transform:Transform=new Transform(art);transform.matrix=new Matrix(m[0],m[1],m[2],m[3],m[4],m[5]);
        art.gotoAndStop(1);s.area=s.ticket.holder.createEmptyMovieClip("area",1);
        var b:Array=s.spec.hitBounds;s.area.beginFill(0,0);s.area.moveTo(b[0],b[1]);s.area.lineTo(b[2],b[1]);
        s.area.lineTo(b[2],b[3]);s.area.lineTo(b[0],b[3]);s.area.lineTo(b[0],b[1]);s.area.endFill();s.area._visible=false;
        s.ready=true;s.phase="idle";
    }
    /** startWave resets tickCount=0, registers ALL spawn-event listeners, then publishes
     * WaveStarted. WaveSpawner.tick increments tickCount before servicing its wheel.
     * An exact target-wave tick>0 therefore cannot precede that listener registration.
     */
    public static function waveReady(s:Object):Boolean {
        var w:Object=s.spawner;
        return owns(s) && w===WaveSpawner.instance && w.gameworld===s.room.world && w.isActive===true && w.isFinished!==true
            && s.room.stageManager.isCleared!==true && w.currentWave===s.spec.subWaveIndex
            && finite(w.tickCount) && w.tickCount>0;
    }
    public static function tick(s:Object):String {
        if(s==null) return "ready";
        if(s.failed) return "failed";
        if(!current(s)) {end(s);return "cancelled";}
        if(!owns(s)) {fail(s,"depth-or-instance-owner-replaced");return "failed";}
        if(!s.ready) {if(++s.age>900) fail(s,"load-timeout");return s.failed?"failed":"loading";}
        if(_root.暂停===true || _root.场景转换中===true || s.room.phase=="loading") return "ready";
        // Clear retires spawning, not the authored vehicle. Keep the final pose until room teardown.
        if(s.room.stageManager.isCleared===true) return "ready";
        var hero:MovieClip=s.room.world[_root.控制目标];
        if(s.phase=="idle") {
            if(hero._parent===s.room.world && finite(hero.hp) && hero.hp>0 && typeof hero.area=="movieclip" && s.area.hitTest(hero.area))
                s.phase="opening";
        } else if(s.phase=="opening") {
            s.frame++;s.art.gotoAndStop(s.frame);
            if(s.frame===29) s.phase="ready-to-dispatch";
        }
        if(s.phase=="ready-to-dispatch" && !s.attempted) {
            if(s.spawner!==WaveSpawner.instance || s.spawner.gameworld!==s.room.world) {fail(s,"wave-owner-replaced");return "failed";}
            if(s.spawner.currentWave>s.spec.subWaveIndex || s.spawner.isFinished===true) {fail(s,"target-wave-retired");return "failed";}
            if(waveReady(s)) {
                // Set the fence BEFORE publication. A listener may commit and then throw.
                s.attempted=true;s.phase="spent";
                try {s.room.world.dispatcher.publish("Cf6TransportReady",s.spec.id);}
                catch(error) {fail(s,"delivery-unknown");return "failed";}
            }
        }
        return "ready";
    }
    public static function fail(s:Object,reason:String):Void {
        if(s==null || s.closed || s.failed) return;s.failed=true;s.phase="failed";s.reason=reason;
    }
    public static function end(s:Object):Void {
        if(s==null || s.closed) return;
        s.closed=true;if(s.loader!=null) s.loader.removeListener(s.listener);
        // Only our ticket is released; the shared depth session also owns doors and other props.
        Cf6PropDepthService.release(s.ticket);
        if(s.room.transportSession===s) s.room.transportSession=null;
    }
}
