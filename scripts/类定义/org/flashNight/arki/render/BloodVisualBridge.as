import org.flashNight.arki.render.VisualRandom;
import org.flashNight.arki.component.Effect.BitmapEffectRenderer;

// Pure decoration: one seeded birth, bounded landing stamps, no active AS2 clips.
class org.flashNight.arki.render.BloodVisualBridge {
    private static var enabled:Boolean=false;
    private static var style:Number=-1;
    private static var nextId:Number=0;
    private static var spawns:Array=[];
    private static var queue:Array=[];
    private static var lastStamp:Number=0;
    private static var spawnDropped:Number=0;
    private static var stampDropped:Number=0;
    private static var stampDuplicates:Number=0;
    private static var stamped:Number=0;

    public static function configure(value:Boolean,index:Number):Void {
        enabled=value===true;
        style=isFinite(index) && index>=0 && index<=63 && index==Math.floor(index)?index:-1;
        if(!enabled){spawns.length=0;queue.length=0;lastStamp=0;}
    }
    public static function disconnect():Void {enabled=false;spawns.length=queue.length=0;lastStamp=0;}
    public static function resetScene():Void {nextId=lastStamp=0;spawns.length=queue.length=0;}
    private static function none():Boolean {
        return org.flashNight.arki.render.WorkerProjectionPolicy.isNone("combatDecoration");
    }
    // False means this paired catalog has not declared ordinary blood yet.
    // Once declared, suppressed/overflowed decoration is consumed without MC fallback.
    public static function trySpawn(x:Number,y:Number,groundZ:Number,scale:Number):Boolean {
        var seed:Number=VisualRandom.eventSeed(4);
        if(style<0)return false;
        if(!enabled || none() || _root.暂停 || !_root.是否视觉元素){spawnDropped++;return true;}
        if(!isFinite(x+y+groundZ+scale) || Math.abs(x)>1000000 || Math.abs(y)>1000000
            || Math.abs(groundZ)>1000000 || scale==0 || Math.abs(scale)>1000){spawnDropped++;return true;}
        var world:MovieClip=_root.gameworld;
        if(!world){spawnDropped++;return true;}
        var sx:Number=world._xscale*.01;
        var px:Number=world._x+x*sx,py:Number=world._y+y*sx;
        if(px<0 || px>Stage.width || py<0 || py>Stage.height){spawnDropped++;return true;}
        if(spawns.length>=64 || nextId>=2147483647){spawnDropped++;return true;}
        var gravity:Number=_root.重力加速度;
        if(!isFinite(gravity) || gravity<0 || gravity>100)gravity=1;
        spawns[spawns.length]="p,"+(++nextId)+","+style+","+x+","+y+","+groundZ+","+scale+","+seed+","+gravity;
        return true;
    }
    // The public combat bridge validates generation/epoch/sequence before calling.
    // stampId is an independent, monotonic C# landing-output id within this scene.
    public static function receiveLandings(poses:Array):Void {
        if(!enabled || none())return;
        if(!(poses instanceof Array) || poses.length>8){stampDropped++;return;}
        for(var i:Number=0;i<poses.length;i++) {
            var pose:Array=poses[i];
            if(!(pose instanceof Array) || pose.length!=4){stampDropped++;continue;}
            var id:Number=pose[0],variant:Number=pose[1],x:Number=pose[2],y:Number=pose[3];
            if(typeof pose[0]!="number" || typeof pose[1]!="number" || typeof pose[2]!="number" || typeof pose[3]!="number"
                || !isFinite(id+variant+x+y) || id<1 || id>2147483647 || id!=Math.floor(id)
                || variant<0 || variant>7 || variant!=Math.floor(variant) || Math.abs(x)>1000000 || Math.abs(y)>1000000){stampDropped++;continue;}
            if(id<=lastStamp){stampDuplicates++;continue;}
            lastStamp=id;
            if(queue.length>=64){stampDropped++;continue;}
            queue[queue.length]={variant:variant,x:x,y:y};
        }
    }
    public static function flush():String {
        if(!enabled || none()){spawns.length=queue.length=0;return "";}
        var payload:String="";
        if(!_root.暂停) {
            for(var i:Number=0;i<spawns.length;i++)payload+=";"+spawns[i];
            var count:Number=queue.length<4?queue.length:4;
            for(i=0;i<count;i++) {
                var pose:Object=queue.shift();
                if(BitmapEffectRenderer.renderBloodstainVariant(pose.x,pose.y,pose.variant))stamped++;
                else stampDropped++;
            }
        }
        spawns.length=0;
        return payload;
    }
    public static function getStats():Object {
        return {policy:"seeded-decoration-v1",enabled:enabled,style:style,queued:spawns.length,
            pendingStamps:queue.length,lastStamp:lastStamp,spawnDropped:spawnDropped,
            stampDropped:stampDropped,stampDuplicates:stampDuplicates,stamped:stamped};
    }
}
