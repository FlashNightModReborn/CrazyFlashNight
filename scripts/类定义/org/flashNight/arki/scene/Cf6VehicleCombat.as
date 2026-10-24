import org.flashNight.arki.scene.Cf6VehicleRules;
import org.flashNight.arki.scene.Cf6VehicleTimeline;
import org.flashNight.arki.scene.Cf6VehicleActorAdapter;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.component.Damage.DamageManagerFactory;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.gesh.depth.DepthManager;

/** Dedicated source-space swept collision; never queries player equipment or credits rewards. */
class org.flashNight.arki.scene.Cf6VehicleCombat {
    public static function nextRandom(s:Object,count:Number):Number {
        s.rng=(s.rng*16807)%2147483647;return Math.floor(s.rng%count);
    }
    public static function playCue(s:Object,key:String,causalHeroDeath:Boolean):Void {
        var death:Boolean=causalHeroDeath===true && key=="vehicleDeath" && !(s.actorAdapter.hero.hp>0) && s.status!="failed";
        if(s.world!==_root.gameworld || s.world.__stageReturnWorldIdentity!==s.owner || s.closed || (PauseManager.isPaused() && !death)) return;
        var sounds:Array=s.data.audio[key];
        if(sounds.length>0 && typeof _root.播放音效=="function") _root.播放音效(sounds[sounds.length==1?0:nextRandom(s,sounds.length)]);
    }
    public static function effect(s:Object,kind:String,x:Number,y:Number):Void {
        if(s.effects.length>=64 || s.world!==_root.gameworld || s.world.__stageReturnWorldIdentity!==s.owner) return;
        var clip:MovieClip=s.world.attachMovie(s.spec.symbols[kind],"__cf6VehicleEffect"+(++s.serial),s.world.getNextHighestDepth());
        if(typeof clip!="movieclip") {s.reason="effect-linkage-missing-"+kind;return;}
        clip.__cf6VehicleOwner=s.token;clip._x=x*s.spec.scale;clip._y=y*s.spec.scale;clip._xscale=clip._yscale=100*s.spec.scale;
        var sparkStarts:Array=[2,31,44,58];
        var first:Number=kind=="spark"?sparkStarts[nextRandom(s,4)]:2;
        clip.gotoAndStop(first);s.effects.push({clip:clip,closed:false,age:0});
        playCue(s,kind=="spark"?"metal":"explosion");
    }
    public static function effects(s:Object):Void {
        for(var i:Number=s.effects.length-1;i>=0;i--) {
            var row:Object=s.effects[i];
            if(!owned(s,row.clip)) {s.reason="owned-effect-replaced";continue;}
            if(row.age>0) Cf6VehicleTimeline.advance(row.clip,false);row.age++;
            if(row.clip.__cf6RemoveSelf===true || row.clip.__cf6RetireVisual===true || row.age>140) {retire(s,row);s.effects.splice(i,1);}
        }
    }
    /** Continuous relative-motion slab intersection in original 2D collision space. */
    public static function hitTime(b:Array,ox:Number,oy:Number,nx:Number,ny:Number,r:Array,ax:Number,ay:Number,bx:Number,by:Number):Number {
        var starts:Array=[ox-ax,oy-ay],deltas:Array=[nx-bx-starts[0],ny-by-starts[1]],enter:Number=0,leave:Number=1;
        for(var axis:Number=0;axis<2;axis++) {
            var lo:Number=r[axis]-b[axis+2],hi:Number=r[axis+2]-b[axis],delta:Number=deltas[axis];
            if(Math.abs(delta)<0.000001) {if(starts[axis]<lo || starts[axis]>hi) return 2;}
            else {
                var near:Number=(lo-starts[axis])/delta,far:Number=(hi-starts[axis])/delta;
                if(near>far) {var swap:Number=near;near=far;far=swap;}
                enter=Math.max(enter,near);leave=Math.min(leave,far);if(enter>leave)return 2;
            }
        }
        return enter;
    }
    public static function overlap(a:Array,x:Number,y:Number,b:Array,u:Number,v:Number):Boolean {
        return x+a[0]<=u+b[2] && x+a[2]>=u+b[0] && y+a[1]<=v+b[3] && y+a[3]>=v+b[1];
    }
    public static function owned(s:Object,clip:MovieClip):Boolean {
        return typeof clip=="movieclip" && clip.__cf6VehicleOwner===s.token
            && clip._parent===s.world && s.world[clip._name]===clip;
    }
    public static function retire(s:Object,row:Object):Void {
        if(row==null || row.closed) return;
        if(owned(s,row.clip)) {
            if(DepthManager.instance!=undefined) DepthManager.instance.removeMovieClip(row.clip);
            row.clip.removeMovieClip();
        }
        row.closed=true;
    }
    public static function hitRoad(s:Object,row:Object,collision:Boolean):Boolean {
        if(row.closed || row.resolved || !owned(s,row.clip)) return false;
        if(!collision) row.clip.hp-=s.spec.projectilePower;
        if(row.kind=="shield" && !collision) {
            var hurtStarts:Array=[1,13];
            Cf6VehicleTimeline.pose(row.clip,50);row.variant=hurtStarts[nextRandom(s,2)];row.variantSource=574;row.variantPending=true;row.hitAge=0;return true;
        }
        row.resolved=true;row.age=0;
        row.knockdown=collision;row.knockDirection=s.actorAdapter.hero._x>row.clip._x?-1:1;
        if(row.generator>=0 && s.generators[row.generator].active===row) {
            s.generators[row.generator].active=null;
            // The original obstacle only releases concurrency; raider terminal
            // events also consume its finite death budget.
            if(row.kind=="raider") s.generators[row.generator].remaining--;
        }
        Cf6VehicleTimeline.pose(row.clip,row.kind=="obstacle"?3:(collision?70:77));
        if(row.kind=="raider") {
            playCue(s,collision?"raiderDown":"raiderDeath");
            if(!collision) {var deathStarts:Array=[1,32,78];row.variant=deathStarts[nextRandom(s,3)];row.variantSource=611;row.variantPending=true;}
            if(collision || row.variant==78) row.clip._xscale=-row.knockDirection*100*s.spec.scale;
        } else if(row.kind=="obstacle") playCue(s,"obstacle");
        if(row.kind=="raider" && s.rules.phase=="road") {
            Cf6VehicleRules.roadDeath(s.rules,s.token,row.identity);
            // Native helper 1805 is already on its stopped frame 1 when play()
            // starts; the 59-frame source therefore needs 58 subsequent ticks.
            if(s.rules.phase=="boss-intro") s.rules.frame=1;
        }
        if(collision) {
            if(row.kind!="shield") playCue(s,"metal");
            if(typeof s.player.p1=="movieclip") s.player.p1.gotoAndStop(2);
        }
        return true;
    }
    public static function fire(s:Object):Void {
        if(s.projectiles.length>=80) return;
        for(var i:Number=0;i<s.data.muzzles.length;i++) {
            var muzzle:Array=s.data.muzzles[i];
            var name:String="__cf6VehicleBullet"+(++s.serial);
            var clip:MovieClip=s.world.attachMovie(s.spec.symbols.bullet,name,s.world.getNextHighestDepth());
            if(typeof clip!="movieclip") {s.reason="bullet-linkage-missing";return;}
            clip.__cf6VehicleOwner=s.token;
            var angle:Number=(nextRandom(s,2)==0?-1:1)*nextRandom(s,5)*3.14/180;
            var row:Object={clip:clip,x:s.actorAdapter.hero._x/s.spec.scale+muzzle[0],
                y:s.actorAdapter.hero.Z轴坐标/s.spec.scale+muzzle[1],age:0,closed:false,
                dx:s.spec.projectileSpeed*Math.cos(angle),dy:s.spec.projectileSpeed*Math.sin(angle)};
            clip._xscale=clip._yscale=s.spec.scale*100;clip._x=row.x*s.spec.scale;clip._y=row.y*s.spec.scale;
            s.projectiles.push(row);s.shots++;playCue(s,"gun");
        }
    }
    public static function projectiles(s:Object):Void {
        for(var i:Number=s.projectiles.length-1;i>=0;i--) {
            var bullet:Object=s.projectiles[i];
            if(!owned(s,bullet.clip)) {bullet.closed=true;s.projectiles.splice(i,1);continue;}
            var oldX:Number=bullet.x,oldY:Number=bullet.y;bullet.x+=bullet.dx;bullet.y+=bullet.dy;bullet.age++;
            var nearest:Object=null,nearestTime:Number=2,wallHit:Boolean=false;
            for(var w:Number=0;w<s.data.walls.length;w++) {
                var wt:Number=hitTime(s.data.bullet,oldX,oldY,bullet.x,bullet.y,s.data.walls[w],0,0,0,0);
                if(wt<nearestTime) {nearestTime=wt;wallHit=true;}
            }
            for(var j:Number=0;j<s.actors.length;j++) {
                var actor:Object=s.actors[j];
                if(actor.closed || actor.resolved || !owned(s,actor.clip)) continue;
                var rect:Array=s.data[actor.kind],x:Number=actor.clip._x/s.spec.scale,y:Number=actor.clip._y/s.spec.scale;
                var time:Number=hitTime(s.data.bullet,oldX,oldY,bullet.x,bullet.y,rect,actor.previousX,actor.previousY,x,y);
                if(time<nearestTime) {nearest=actor;nearestTime=time;wallHit=false;}
            }
            var bossHit:Boolean=false;
            if(s.rules.phase=="boss" && owned(s,s.boss) && s.boss.hp>0) {
                var bt:Number=hitTime(s.data.bullet,oldX,oldY,bullet.x,bullet.y,s.data.boss,s.bossPreviousX,s.bossPreviousY,s.boss._x/s.spec.scale,s.boss._y/s.spec.scale);
                if(bt<nearestTime) {bossHit=true;wallHit=false;nearestTime=bt;}
            }
            var hitX:Number=oldX+(bullet.x-oldX)*nearestTime,hitY:Number=oldY+(bullet.y-oldY)*nearestTime;
            if(bossHit) {s.boss.hp=Math.max(0,s.boss.hp-s.spec.projectilePower);s.bossHits++;effect(s,"spark",hitX,hitY);}
            else if(wallHit) effect(s,"spark",hitX,hitY);
            else if(nearest!=null) {
                hitRoad(s,nearest,false);
                if(nearest.kind=="shield") effect(s,"spark",hitX,hitY);
                else if(typeof _root.效果=="function") _root.效果("飙血",hitX*s.spec.scale,hitY*s.spec.scale);
            }
            bullet.clip._x=bullet.x*s.spec.scale;bullet.clip._y=bullet.y*s.spec.scale;
            if(bullet.age>1) Cf6VehicleTimeline.advance(bullet.clip,true);
            if(bossHit || wallHit || nearest!=null || bullet.clip.__cf6RetireVisual===true || bullet.age>=14
                    || Math.abs(bullet.x-s.actorAdapter.hero._x/s.spec.scale)>800 || Math.abs(bullet.y-s.actorAdapter.hero.Z轴坐标/s.spec.scale)>800) {
                retire(s,bullet);s.projectiles.splice(i,1);
            }
        }
    }
    public static function damageHero(s:Object,grenade:Object):Boolean {
        if(grenade.attempted || !owned(s,grenade.clip) || !owned(s,s.boss)
                || !Cf6VehicleActorAdapter.current(s.actorAdapter) || !(s.actorAdapter.hero.hp>0)) return false;
        // Set before dispatch. Exceptions/unknown consumer outcome are not replayable.
        grenade.attempted=true;
        var hero:MovieClip=s.actorAdapter.hero;
        var bullet:Object={伤害类型:"真伤",子弹威力:0,固伤:hero.hp满血值*30/s.spec.sourcePlayerHealth,
            霰弹值:1,命中率:100000,是否为敌人:true,flags:0,hitCount:0,击倒率:0,
            发射者:s.boss._name,子弹种类:"CF6VehicleGrenade",方向:"左",击中地图效果:"",击中后子弹的效果:""};
        if(!(bullet.固伤>0) || DamageManagerFactory.Basic==undefined) {s.reason="damage-authority-missing";return false;}
        bullet.damageManager=DamageManagerFactory.Basic.getDamageManager(bullet);
        var hpBefore:Number=hero.hp;
        try {
            BulletQueueProcessor.injectHit(bullet,s.boss,hero,hero._x,hero._y,1,false);
        } catch(error) {s.reason="grenade-delivery-unknown";return false;}
        if(hero.hp<hpBefore) s.grenadeHits++;
        if(typeof s.player.p1=="movieclip") s.player.p1.gotoAndStop(2);
        return true;
    }
}
