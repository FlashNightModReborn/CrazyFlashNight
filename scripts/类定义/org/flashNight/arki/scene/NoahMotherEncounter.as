import org.flashNight.arki.scene.StageManager;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.dialogue.NativeDialogueService;
import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.arki.unit.Action.Regeneration.HealApplier;
import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.neur.Event.EventDispatcher;

/** 尸母巢穴末图。生产数是衰竭权威，原生素材仅显示状态，不持有另一套生产额度。 */
class org.flashNight.arki.scene.NoahMotherEncounter {
    public static var MAX_UNITS:Number=18;
    public static var MAX_MOTHERS:Number=2;
    public static var LIQUID_PERIOD:Number=240;
    public static var ACID_THRESHOLD:Number=9;
    public static var ACID_POWER:Number=1500;
    public static var POOL_LIFE:Number=180;
    public static var POOL_PULSE:Number=15;
    public static var POOL_RADIUS_X:Number=248;
    public static var POOL_RADIUS_Y:Number=115.2;
    public static var POOL_SCALE:Number=160;
    public static var SERUM_FRACTION:Number=1/18;
    public static var DEATH_FRAMES:Number=90;
    // 复用已预载的短音效；不在素材时间轴、持续判定或每个受影响单位上重复挂声。
    private static var SFX:Object={hoist:"金属刮擦.wav",reveal:"克隆怪嘶吼3.wav",
        charge:"blood6.wav",expel:"blood7.wav",acid:"m1014毒液.wav",serum:"blood5.wav",
        rupture:"soundheadexplode.wav",death:"克隆怪嘶吼2.wav",chain:"火凤_链条.wav",fall:"地震3.wav"};
    private static var room:Object;
    private static var watch:MovieClip;
    private static var installed:Boolean=false;

    public static function start():Void {
        teardown();
        if(!installed){installed=true;NativeInteractionContext.onSceneTeardown(teardown);}
        var w:MovieClip=_root.gameworld;
        room={world:w,owner:StageReturnFlow.worldIdentity(w),units:[],effects:[],pools:[],deathFrame:0,
            frame:0,primary:0,larvae:0,primaryTotal:12,larvaTotal:6,phase:0,
            pose:"登场",poseFrame:0,nextLiquid:330,nextLarva:165,pending:null,flight:null,
            serial:0,art:null,closed:false,soundPhase:0};
        w.__noahMotherEncounter=NoahMotherEncounter;
        _global.ASSetPropFlags(w,["__noahMotherEncounter"],1,false);
        w.dispatcher.subscribeOnce("Clear",teardown,NoahMotherEncounter);
        w.dispatcher.subscribeOnce("StageFailed",teardown,NoahMotherEncounter);
        watch=_root.createEmptyMovieClip("__noahMotherWatch",_root.getNextHighestDepth());
        watch.onEnterFrame=function():Void {org.flashNight.arki.scene.NoahMotherEncounter.tick();};
    }
    private static function current():Boolean {
        return room!=null && !room.closed && room.world===_root.gameworld
            && room.owner===StageReturnFlow.worldIdentity(_root.gameworld);
    }
    private static function paused():Boolean {
        return _root.暂停===true || _root.场景转换中===true || NativeDialogueService.hasActiveSession();
    }
    private static function valid(row:Object):Boolean {
        var u:MovieClip=row.unit;
        return u._name!=undefined && room.world[u._name]===u && u.__noahBirth===row.token;
    }
    private static function counts():Object {
        var n:Number=0;var mothers:Number=0;
        for(var i:Number=room.units.length-1;i>=0;i--){
            var row:Object=room.units[i];
            if(!valid(row)){room.units.splice(i,1);continue;}
            // attachMovie 的初始化可延迟到下一帧；已接纳但尚无 hp 的实例同样占位。
            if(row.unit.hp>0 || row.unit.hp==undefined){n++;if(row.mother)mothers++;}
        }
        return {units:n,mothers:mothers};
    }
    public static function canProduce(amount:Number,mothers:Boolean):Boolean {
        if(!current())return true;
        if(room.closed || paused())return false;
        var c:Object=counts();
        return c.units+amount<=MAX_UNITS-1 && (!mothers || c.mothers+amount<=MAX_MOTHERS);
    }
    public static function acceptSpawn(id:String,init:Object):Boolean {
        if(!current() || init.是否为敌人!==true)return true;
        if(paused())return false;
        var c:Object=counts();
        var primary:Boolean=init.noahPrimary===true;
        if(primary && room.primary>=room.primaryTotal)return false;
        if(id=="敌人-普通尸母" && c.mothers>=MAX_MOTHERS)return false;
        return c.units<(primary?MAX_UNITS:MAX_UNITS-1);
    }
    public static function registered(u:MovieClip,init:Object):Void {
        if(!current() || u==undefined || init.是否为敌人!==true)return;
        var token:Object={};u.__noahBirth=token;
        room.units.push({unit:u,token:token,mother:init.兵种=="敌人-普通尸母",
            primary:init.noahPrimary===true,large:init.noahLarge===true});
        if(init.noahPrimary===true)room.primary++;
        if(init.noahLarge===true)room.larvae++;
        updatePhase();
    }
    private static function updatePhase():Void {
        var made:Number=room.primary+room.larvae;
        room.phase=made>=room.primaryTotal+room.larvaTotal?2:(made>=9?1:0);
    }
    /** 波次本身仍计算12只正式尸母；这里只补尚未生产的大虫及其可能转化出的尸母。 */
    public static function requiredCount():Number {
        if(!current())return 0;
        counts();
        var n:Number=room.larvaTotal-room.larvae;
        for(var i:Number=0;i<room.units.length;i++){
            var row:Object=room.units[i];var u:MovieClip=row.unit;
            if(row.mother && !row.primary && (u.hp>0 || u.hp==undefined))n++;
            else if(row.large && (u.hp>0 || !u.__noahTransformed))n++;
        }
        // 最后一名护卫提前死亡时，仍让断索下坠完成后再结算。
        return n>0?n:((room.phase==2 && room.deathFrame<DEATH_FRAMES)?1:0);
    }
    public static function tick():Void {
        if(!current()){teardown();return;}
        var sm:Object=StageManager.instance;
        if(sm.isFailed || sm.isFinished || room.world.关卡结束===true){teardown();return;}
        if(paused())return;
        var art:MovieClip=room.world.stageInstance0;
        if(art.noahAssetVersion!==1)return;
        room.art=art;room.frame++;
        updateEffects();updatePools();updateFlight();
        if(room.phase==2){
            room.pose="结束";room.deathFrame=Math.min(DEATH_FRAMES,room.deathFrame+1);
            room.poseFrame=room.deathFrame;room.pending=null;
        }
        else {
            room.poseFrame++;
            if(room.pose=="登场" && room.poseFrame>150){room.pose="空闲";room.poseFrame=1;}
            else if(room.pose=="喷吐"){
                if(room.poseFrame==25)release();
                if(room.poseFrame>66){room.pose="空闲";room.poseFrame=1;room.pending=null;}
            } else if(room.pose=="空闲"){
                if(room.poseFrame>80)room.poseFrame=1;
                if(room.frame>=room.nextLiquid)beginSpit(false);
                else if(room.larvae<room.larvaTotal && room.frame>=room.nextLarva
                    && room.primary>=room.larvae*2+1 && canProduce(1,false))beginSpit(true);
            }
        }
        var charge:String=(room.pose=="喷吐" && room.pending!=null && room.pending.kind!="larva")?room.pending.kind:"";
        art.noahPose(room.pose,room.poseFrame,room.phase,charge,room.frame);
        poseSounds();
    }
    private static function cue(key:String):Void {
        // 沿用正式入口的静音、SFX 预算及连接未就绪时丢弃规则，不补播旧动作。
        if(typeof _root.播放音效=="function")_root.播放音效(SFX[key]);
    }
    private static function poseSounds():Void {
        if(room.phase>room.soundPhase){
            room.soundPhase=room.phase;
            if(room.phase==1)cue("rupture");
        }
        if(room.pose=="登场"){
            if(room.poseFrame==1)cue("hoist");
            else if(room.poseFrame==80)cue("reveal");
        }else if(room.pose=="结束"){
            if(room.deathFrame==1){cue("rupture");cue("death");}
            else if(room.deathFrame==19)cue("chain");
            else if(room.deathFrame==70)cue("fall");
            // 第19帧开始断索下坠；第70帧身体完全隐去。终帧90停留不重播。
        }
    }
    /** 无敌人仍有25%酸液；到9名敌人线性上升至100%。每次蓄力只抽一次。 */
    public static function acidChance(enemies:Number):Number {
        return 0.25+0.75*Math.min(1,Math.max(0,enemies)/ACID_THRESHOLD);
    }
    private static function beginSpit(larva:Boolean):Void {
        var hero:MovieClip=room.world[_root.控制目标];
        if(!larva && !(hero.hp>0))return;
        room.pending={kind:larva?"larva":(Math.random()<acidChance(counts().units)?"acid":"serum"),
            x:hero._x,y:isNaN(hero.Z轴坐标)?hero._y:hero.Z轴坐标};
        room.pose="喷吐";room.poseFrame=1;
        // 周期在预告开始时锁定；满员或暂停没有积攒的补发队列。
        if(larva)room.nextLarva=room.frame+180;
        else room.nextLiquid=room.frame+LIQUID_PERIOD;
        cue("charge");
    }
    private static function release():Void {
        var p:Object=room.pending;
        if(p==null)return;
        if(p.kind=="larva"){
            if(!canProduce(1,false))return;
            var init:Object={_x:900+random(150),_y:400+random(36),等级:41,名字:"基因虫",
                是否为敌人:true,身高:450,noahLarge:true};
            _root.加载游戏世界人物("敌人-普通基因虫","巢穴巨型基因虫"+room.larvae,
                room.world.getNextHighestDepth(),init);
            cue("expel");
            return;
        }
        var mouth:Object=room.art.noahMouth();
        room.art.localToGlobal(mouth);room.world.globalToLocal(mouth);
        var fx:MovieClip=effect(p.kind+"Drop",mouth.x,mouth.y,100);
        room.flight={kind:p.kind,x:p.x,y:p.y,sx:mouth.x,sy:mouth.y,age:0,fx:fx};
        cue("expel");
    }
    private static function effect(id:String,x:Number,y:Number,scale:Number):MovieClip {
        var fx:MovieClip=room.art.attachMovie("Noah_"+id,"noahFx"+(++room.serial),10000+room.serial);
        position(fx,x,y);fx._xscale=fx._yscale=scale;return fx;
    }
    private static function position(fx:MovieClip,x:Number,y:Number):Void {
        var p:Object={x:x,y:y};room.world.localToGlobal(p);room.art.globalToLocal(p);
        fx._x=p.x;fx._y=p.y;
    }
    private static function updateFlight():Void {
        var f:Object=room.flight;if(f==null)return;
        f.age++;var t:Number=f.age/36;
        position(f.fx,f.sx+(f.x-f.sx)*t,f.sy+(f.y-f.sy)*t-260*4*t*(1-t));
        f.fx._rotation=t*130;
        if(f.age>=36){
            f.fx.removeMovieClip();
            room.flight=null;impact(f.kind,f.x,f.y);
        }
    }
    private static function inArea(u:MovieClip,x:Number,y:Number):Boolean {
        var z:Number=isNaN(u.Z轴坐标)?u._y:u.Z轴坐标;
        var dx:Number=(u._x-x)/POOL_RADIUS_X;var dy:Number=(z-y)/POOL_RADIUS_Y;
        return dx*dx+dy*dy<=1;
    }
    /** 地面液体持续6秒，半秒一次；同种区域替换，不产生叠层连秒。 */
    public static function impact(kind:String,x:Number,y:Number):Void {
        if(!current() || paused())return;
        for(var i:Number=room.pools.length-1;i>=0;i--){
            if(room.pools[i].kind==kind){room.pools[i].fx.removeMovieClip();room.pools.splice(i,1);}
        }
        var splash:MovieClip=effect(kind+"Splash",x,y,POOL_SCALE);
        room.effects.push({fx:splash,age:0,life:15});
        var surface:MovieClip=effect(kind+"Splash",x,y,POOL_SCALE);surface.gotoAndStop(2);
        var pool:Object={kind:kind,x:x,y:y,fx:surface,born:room.frame,
            expires:room.frame+POOL_LIFE,nextPulse:room.frame+POOL_PULSE};
        room.pools.push(pool);cue(kind);pulsePool(pool);
    }
    private static function updatePools():Void {
        for(var i:Number=room.pools.length-1;i>=0;i--){
            var p:Object=room.pools[i];var left:Number=p.expires-room.frame;
            if(left<=0){p.fx.removeMovieClip();room.pools.splice(i,1);continue;}
            p.fx._alpha=(65+8*Math.sin((room.frame-p.born)*0.22))*Math.min(1,left/30);
            if(room.frame>=p.nextPulse){p.nextPulse=room.frame+POOL_PULSE;pulsePool(p);}
        }
    }
    private static function pulsePool(p:Object):Void {
        var targets:Array=[];
        for(var name:String in room.world){
            var u:MovieClip=room.world[name];
            if(typeof u=="movieclip" && u.hp>0 && !u.element && u.dispatcher!=null && inArea(u,p.x,p.y))targets.push(u);
        }
        for(var i:Number=0;i<targets.length;i++){
            if(p.kind=="acid")acidHit(targets[i],p.x,p.y);
            else healPulse(targets[i]);
        }
    }
    private static function acidHit(u:MovieClip,x:Number,y:Number):Void {
        if(room.emitter==null){
            var e:MovieClip=room.world.createEmptyMovieClip("__noahAcidEmitter",room.world.getNextHighestDepth());
            e.是否为敌人=true;e.等级=41;e.命中率=100000;e.伤害加成=0;e.方向="右";
            e.dispatcher=new EventDispatcher();room.emitter=e;
            _global.ASSetPropFlags(room.world,["__noahAcidEmitter"],1,false);
        }
        var shooter:MovieClip=room.emitter;shooter._x=x;shooter._y=shooter.Z轴坐标=y;
        var data:Object={声音:"",霰弹值:1,子弹散射度:0,发射效果:"",子弹种类:"普通爆炸",
            子弹威力:ACID_POWER,子弹速度:0,Z轴攻击范围:POOL_RADIUS_Y,击倒率:1,不硬直:false,
            水平击退速度:8,垂直击退速度:0,命中率:100000,击中地图效果:"",击中后子弹的效果:"",
            伤害类型:"魔法",魔法伤害属性:"巢蚀",友军伤害:true,子弹敌我属性:true,
            发射者:shooter._name,shootX:x,shootY:y,shootZ:y};
        var bullet:Object=BulletFactory.createSettlementBullet(data,shooter);
        BulletQueueProcessor.injectHit(bullet,shooter,u,u._x,u._y,1,true);
    }
    /** 一片母液12次判定，共回复2/3最大生命；离开即停止，无离场余效或叠加状态。 */
    private static function healPulse(u:MovieClip):Void {
        var restored:Number=HealApplier.applyHpCapped(u,u.hp满血值*SERUM_FRACTION,u.hp满血值);
        if(!(restored>0))return;
        var fx:MovieClip=effect("serumDrop",u._x,u._y-40,24);
        room.effects.push({fx:fx,age:0,life:18,rise:true});
    }
    private static function updateEffects():Void {
        for(var i:Number=room.effects.length-1;i>=0;i--){
            var e:Object=room.effects[i];e.age++;e.fx._alpha=100*(1-e.age/e.life);
            if(e.rise)e.fx._y-=1;
            if(e.age>=e.life){e.fx.removeMovieClip();room.effects.splice(i,1);}
        }
    }
    public static function snapshot():Object {
        if(!current())return null;
        var c:Object=counts();return {primary:room.primary,larvae:room.larvae,phase:room.phase,
            frame:room.frame,units:c.units,mothers:c.mothers,required:requiredCount(),
            pools:room.pools.length,deathFrame:room.deathFrame,pose:room.pose,poseFrame:room.poseFrame,kind:room.pending.kind,x:room.pending.x,y:room.pending.y};
    }
    public static function teardown():Void {
        if(watch!=null){delete watch.onEnterFrame;watch.removeMovieClip();watch=null;}
        if(room==null)return;
        room.closed=true;
        if(room.world.__noahMotherEncounter===NoahMotherEncounter)delete room.world.__noahMotherEncounter;
        if(room.emitter!=null)room.emitter.removeMovieClip();
        for(var i:Number=0;i<room.effects.length;i++)room.effects[i].fx.removeMovieClip();
        for(var j:Number=0;j<room.pools.length;j++)room.pools[j].fx.removeMovieClip();
        room.flight.fx.removeMovieClip();
        room=null;
    }
}
