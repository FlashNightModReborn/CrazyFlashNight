import org.flashNight.arki.component.Effect.EffectSystem;
/** Visual-only exit guidance. Clear/navigation authority remains with StageManager. */
class org.flashNight.arki.scene.Cf6ExitGuideService {
    private static var serial:Number=0;
    private static function finite(value):Boolean {
        return typeof value=="number" && (value-value)==0 && Math.abs(value)<1000000;
    }
    private static function current(h:Object):Boolean {
        var s:Object=h.room;
        return h!=null && !h.closed && s!=null && s.world===_root.gameworld
            && s.owner===s.world.__stageReturnWorldIdentity && s.world.__cf6Mechanism===s
            && h.world===s.world && h.owner===s.owner
            && s.stageManager===org.flashNight.arki.scene.StageManager.instance
            && s.stageIndex===s.stageManager.currentStage
            && s.stageManager.isFailed!==true && s.stageManager.isFinished!==true
            && h.clip.__cf6ExitGuideOwner===h.token && h.clip._parent===h.world;
    }
    private static function roomCurrent(room:Object):Boolean {
        return room!=null && room.world===_root.gameworld && room.owner!==undefined
            && room.owner===room.world.__stageReturnWorldIdentity && room.world.__cf6Mechanism===room
            && room.stageManager===org.flashNight.arki.scene.StageManager.instance
            && room.stageIndex===room.stageManager.currentStage
            && room.stageManager.isFailed!==true && room.stageManager.isFinished!==true && room.failed!==true;
    }
    /** Projection receipt only; it never opens the exit or publishes Clear. */
    public static function showClearCue(room:Object,hero:MovieClip):Boolean {
        if(!roomCurrent(room) || room.clearRequested!==true || room.clearCueIssued===true
                || hero==undefined || hero._parent!==room.world || !(hero.hp>0) || !hero._visible
                || !finite(hero._x) || !finite(hero._y)) return false;
        // Latch before the visual call: a partially created effect must not be replayed.
        room.clearCueIssued=true;
        try {EffectSystem.Effect("小过关提示动画",hero._x,hero._y,100);}
        catch(error) {trace("[CF6] clear cue projection failed: "+error);}
        return true;
    }
    /** StageManager calls this before its ordinary clear animation, after real clear. */
    public static function hasClearCue(manager:Object,world:MovieClip):Boolean {
        var room:Object=world.__cf6Mechanism;
        return roomCurrent(room) && room.stageManager===manager && room.world===world
            && room.clearRequested===true && room.clearCueIssued===true;
    }
    public static function begin(room:Object,guidePoint:Object):Object {
        if(room==null || room.world!==_root.gameworld || room.owner!==room.world.__stageReturnWorldIdentity
                || room.world.__cf6Mechanism!==room) return null;
        // A traversal's real acquisition gate takes precedence over an optional ordinary-exit hint.
        var point:Object=room.departure.spec.gate;
        if(point==undefined) point=guidePoint;
        if(point==undefined || !finite(point.x) || !finite(point.z)) return null;
        var direction:String=point.direction;
        if(direction==undefined) {
            var heading:String=room.departure.rules.heading;
            direction=heading=="左" || heading=="右" ? heading : "上";
        }
        // 三段箭头连同线宽都留在自动接管圈内；普通手动出口保持原尺寸。
        var drawScale:Number=finite(point.radius) && point.radius>0 && point.radius<300
            ? Math.min(1,point.radius/50) : 1;
        if(direction!="上" && direction!="下" && direction!="左" && direction!="右") return null;
        var token:Object={},name:String="__cf6ExitGuide"+(++serial);
        var clip:MovieClip=room.world.createEmptyMovieClip(name,room.world.getNextHighestDepth());
        clip.__cf6ExitGuideOwner=token;clip._x=point.x;clip._y=point.z;
        clip._rotation=direction=="右"?90:direction=="下"?180:direction=="左"?270:0;
        var h:Object={room:room,world:room.world,owner:room.owner,clip:clip,token:token,closed:false,ready:undefined,drawScale:drawScale};
        tick(h);return h.closed?null:h;
    }
    private static function draw(clip:MovieClip,ready:Boolean,scale:Number):Void {
        clip.clear();clip.lineStyle(scale,0x26320D,100);
        clip.beginFill(ready?0xC6F600:0x88917B,100);
        // The tip is the actual world gate; three arrows lead toward it from walkable foreground.
        for(var i:Number=0;i<3;i++) {
            var y:Number=i*17*scale;
            clip.moveTo(0,y);clip.lineTo(-7*scale,y+12*scale);clip.lineTo(7*scale,y+12*scale);clip.lineTo(0,y);
        }
        clip.endFill();
    }
    public static function tick(h:Object):Void {
        if(h==null || h.closed) return;
        if(!current(h) || h.room.failed===true) {end(h);return;}
        var ready:Boolean=h.room.clearRequested===true;
        if(h.ready!==ready) {draw(h.clip,ready,h.drawScale);h.ready=ready;}
        h.clip._alpha=ready?100:45;
        var departure:Object=h.room.departure;
        h.clip._visible=departure==null || departure.rules.phase=="waiting";
    }
    public static function end(h:Object):Void {
        if(h==null || h.closed) return;h.closed=true;
        // An ordinary token guards same-name AVM1 aliases and foreign ownership changes.
        if(h.clip.__cf6ExitGuideOwner===h.token && h.clip._parent===h.world) h.clip.removeMovieClip();
    }
}
