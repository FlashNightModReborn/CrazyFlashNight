import org.flashNight.arki.scene.NoahMotherEncounter;
import org.flashNight.arki.scene.StageManager;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.neur.Event.LifecycleEventDispatcher;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.component.Damage.UniversalDamageHandle;
import org.flashNight.arki.component.Damage.DamageResult;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.component.Damage.DamageManagerFactory;
import org.flashNight.arki.component.StatHandler.DodgeHandler;
import org.flashNight.arki.unit.UnitComponent.Status.ImpactStateHandler;
import org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine;
import flash.display.BitmapData;
import flash.geom.Matrix;

/** 原生 MovieClip / 世界切换 / 正式伤害处理器与发布素材回归，不写存档。 */
class org.flashNight.arki.scene.NoahMotherEncounterTest {
    private static var passed:Number=0;
    private static var failed:Number=0;
    private static var world:MovieClip;
    private static var seq:Number=0;
    private static var loaded:MovieClip;
    private static var loader:MovieClipLoader;
    private static var listener:Object;
    private static var saved:Object;
    private static var hits:Array;
    private static var sounds:Array;
    public static function runAllTests():Void {
        saved={world:_root.gameworld,hero:_root.控制目标,pause:_root.暂停,transition:_root.场景转换中,
            spawn:_root.加载游戏世界人物,sound:_root.播放音效};
        _root.播放音效=function(id:String):Void {org.flashNight.arki.scene.NoahMotherEncounterTest.recordSound(id);};
        _root.暂停=false;_root.场景转换中=false;_root.控制目标="hero";
        StageManager.getInstance().isFailed=false;StageManager.instance.isFinished=false;
        _root.加载游戏世界人物=function(id:String,name:String,depth:Number,init:Object):MovieClip {
            var api:Object=org.flashNight.arki.scene.NoahMotherEncounter;
            if(!api.acceptSpawn(id,init))return null;
            var u:MovieClip=_root.gameworld.createEmptyMovieClip(name,depth);
            for(var k:String in init)u[k]=init[k];init.兵种=id;
            u.hp=u.hp满血值=1000;u.dispatcher=new org.flashNight.neur.Event.EventDispatcher();
            api.registered(u,init);return u;
        };
        testCapacity();testProgress();testLiquids();testRealAcidSettlement();testResistance();testLifecycle();testAudio();
        loadArt();
    }
    private static function room():Void {
        NoahMotherEncounter.teardown();if(world!=null)world.removeMovieClip();sounds=[];
        world=_root.createEmptyMovieClip("noahTestWorld"+(++seq),_root.getNextHighestDepth());
        _root.gameworld=world;StageReturnFlow.worldIdentity(world);
        world.dispatcher=new LifecycleEventDispatcher(world);
        var art:MovieClip=world.createEmptyMovieClip("stageInstance0",1);
        art.noahAssetVersion=1;art.noahPose=function():Void {};
        art.noahMouth=function():Object {return {x:330,y:258};};
        var hero:MovieClip=world.createEmptyMovieClip("hero",2);
        hero.hp=500;hero.hp满血值=1000;hero._x=500;hero._y=hero.Z轴坐标=300;
        hero.是否为敌人=false;hero.dispatcher=new EventDispatcher();
        NoahMotherEncounter.start();
    }
    private static function unit(mother:Boolean,primary:Boolean,large:Boolean):MovieClip {
        var init:Object={是否为敌人:true,noahPrimary:primary,noahLarge:large};
        return _root.加载游戏世界人物(mother?"敌人-普通尸母":"敌人-普通基因虫",
            "unit"+(++seq),world.getNextHighestDepth(),init);
    }
    private static function ticks(n:Number):Void {for(var i:Number=0;i<n;i++)NoahMotherEncounter.tick();}
    private static function check(v:Boolean,label:String):Void {
        if(v)passed++;else {failed++;trace("[FAIL] NoahMotherEncounterTest: "+label);}
    }
    private static function testCapacity():Void {
        room();var a:MovieClip;
        for(var i:Number=0;i<17;i++)a=unit(false,false,false);
        check(NoahMotherEncounter.snapshot().units==17,"descendants occupy the shared cap");
        check(!NoahMotherEncounter.canProduce(1,false),"last slot is reserved for a primary mother");
        check(unit(false,false,false)==null,"loader rejects bypass births");
        check(NoahMotherEncounter.snapshot().primary==0,"rejected spawn never spends vitality");
        var primary:MovieClip=unit(true,true,false);
        check(primary!=null && NoahMotherEncounter.snapshot().units==18,"reserved primary spawn reaches hard cap");
        check(unit(true,true,false)==null,"hard cap cannot be exceeded by primary waves");
        a.hp=0;check(NoahMotherEncounter.snapshot().units==17,"dead units release live population");
        a.removeMovieClip();check(NoahMotherEncounter.snapshot().units==17,"removed corpse does not release twice");
        primary.hp=0;check(NoahMotherEncounter.canProduce(1,false),"offspring resume after space is free");
        room();a=unit(true,false,false);var b:MovieClip=unit(true,true,false);
        check(!NoahMotherEncounter.canProduce(1,true),"transformed and primary mothers share two slots");
        check(unit(true,true,false)==null,"primary wave also respects the mother cap");
        a.hp=0;check(NoahMotherEncounter.canProduce(1,true),"mother death restores mother slot");
        _root.暂停=true;check(!NoahMotherEncounter.canProduce(1,false),"paused production rejected");
        check(unit(false,false,false)==null,"paused loader cannot spend production");_root.暂停=false;
    }
    private static function testProgress():Void {
        room();check(NoahMotherEncounter.snapshot().required==6,"unborn large larvae block premature finish");
        var a:MovieClip;
        for(var i:Number=0;i<8;i++){a=unit(true,true,false);a.hp=0;}
        check(NoahMotherEncounter.snapshot().phase==0,"already wounded base survives first eight births");
        a=unit(false,false,true);a.hp=0;
        check(NoahMotherEncounter.snapshot().phase==1,"ninth actual root birth selects second damage state");
        check(NoahMotherEncounter.requiredCount()==6,"transforming large larva retains finish obligation");
        a.__noahTransformed=true;check(NoahMotherEncounter.requiredCount()==5,"finished larva transformation releases its obligation");
        var child:MovieClip=unit(true,false,false);
        check(NoahMotherEncounter.requiredCount()==6,"new transformed mother keeps pressure until killed");
        child.hp=0;
        for(i=8;i<12;i++){a=unit(true,true,false);a.hp=0;}
        for(i=1;i<6;i++){a=unit(false,false,true);a.hp=0;a.__noahTransformed=true;}
        check(NoahMotherEncounter.snapshot().phase==2,"all eighteen real births exhaust the giant");
        check(NoahMotherEncounter.requiredCount()==1,"early guard clear waits for the final fall");
        check(unit(true,true,false)==null,"primary budget cannot restart");
        a=unit(false,false,false);check(a!=null,"existing ordinary mothers can still provide final pressure");
        ticks(1);check(NoahMotherEncounter.snapshot().pose=="结束","exhaustion immediately ends giant attacks");
        _root.暂停=true;ticks(60);
        check(NoahMotherEncounter.snapshot().deathFrame==1,"pause freezes the death performance");_root.暂停=false;
        ticks(88);check(NoahMotherEncounter.requiredCount()==1,"cannot finish one frame before fall ends");
        ticks(1);check(NoahMotherEncounter.requiredCount()==0 && NoahMotherEncounter.snapshot().deathFrame==90,"fall ends without an ordinary descendant tail");
    }
    private static function testLiquids():Void {
        check(NoahMotherEncounter.acidChance(0)==0.25 && NoahMotherEncounter.acidChance(-1)==0.25,"empty room retains one-in-four acid pressure");
        check(NoahMotherEncounter.acidChance(3)==0.5 && NoahMotherEncounter.acidChance(6)==0.75,"acid probability rises continuously with population");
        check(NoahMotherEncounter.acidChance(9)==1 && NoahMotherEncounter.acidChance(18)==1,"threshold and crowded rooms guarantee acid");
        var oldRandom:Function=Math.random;
        var lowRandom:Function=function():Number {return 0.1;};Math.random=lowRandom;
        var randomReadOnly:Boolean=Math.random!==lowRandom;
        if(randomReadOnly){_global.ASSetPropFlags(Math,"random",0,4);Math.random=lowRandom;}
        check(Math.random===lowRandom,"native random hook is actually installed for deterministic draws");
        room();ticks(330);check(NoahMotherEncounter.snapshot().kind=="acid","low population can actually draw acid");
        Math.random=function():Number {return 0.9;};room();
        var art:MovieClip=world.stageInstance0;art.attachments=[];
        art.attachMovie=function(id:String,name:String,depth:Number):MovieClip {this.attachments.push(id);return this.createEmptyMovieClip(name,depth);};
        ticks(330);var s:Object=NoahMotherEncounter.snapshot();
        check(s.kind=="serum" && s.x==500 && s.y==300,"low population can draw serum and lock the aimed position");
        world.hero._x=900;for(var i:Number=0;i<10;i++)unit(false,false,false);
        ticks(12);s=NoahMotherEncounter.snapshot();
        check(s.kind=="serum" && s.x==500,"population and movement cannot reroll an announced shot");
        _root.暂停=true;var before:Number=s.frame;ticks(45);
        check(NoahMotherEncounter.snapshot().frame==before && NoahMotherEncounter.snapshot().poseFrame==s.poseFrame,"pause freezes charge and progress");_root.暂停=false;
        ticks(12);check(art.attachments.length==1 && art.attachments[0]=="Noah_serumDrop" && NoahMotherEncounter.snapshot().pools==0,"release shows only airborne liquid with no ground marker");
        ticks(35);check(art.attachments.length==1 && NoahMotherEncounter.snapshot().pools==0,"no surface or area effect throughout flight");
        ticks(1);check(art.attachments.length==3 && NoahMotherEncounter.snapshot().pools==1,"surface appears exactly on landing");
        ticks(180);check(NoahMotherEncounter.snapshot().kind=="acid","crowded next cycle chooses acid regardless of random draw");Math.random=oldRandom;
        if(randomReadOnly)_global.ASSetPropFlags(Math,"random",4,0);
        room();world.hero.hp=100;
        var enemy:MovieClip=unit(false,false,false);enemy._x=530;enemy._y=enemy.Z轴坐标=320;enemy.hp=2000;enemy.hp满血值=20000;
        NoahMotherEncounter.impact("serum",500,300);
        check(Math.abs((world.hero.hp-100)/1000-1/18)<0.00001 && Math.abs((enemy.hp-2000)/20000-1/18)<0.00001,"first serum pulse uses each target's own maximum HP");
        ticks(120);check(Math.abs(world.hero.hp-600)<0.001 && Math.abs(enemy.hp-12000)<0.001,"nine contact pulses restore half HP at both health scales");
        enemy._x=900;var leftHp:Number=enemy.hp;ticks(45);
        check(enemy.hp==leftHp,"leaving serum immediately stops further healing");
        check(Math.abs(world.hero.hp-(100+1000*2/3))<0.001,"full exposure restores exactly two-thirds max HP");
        var fullHp:Number=world.hero.hp;ticks(15);
        check(world.hero.hp==fullHp && NoahMotherEncounter.snapshot().pools==0,"expiry adds no extra heal and leaves no lingering regeneration");
        check(NoahMotherEncounter.snapshot().primary==0 && NoahMotherEncounter.snapshot().phase==0,"healing cannot reverse or spend boss progress");
        room();world.hero._x=900;enemy=unit(false,false,false);enemy._x=900;enemy._y=enemy.Z轴坐标=300;enemy.hp=100;
        NoahMotherEncounter.impact("serum",500,300);ticks(15);enemy._x=500;ticks(15);
        check(Math.abs(enemy.hp-(100+1000/18))<0.001,"late entrant receives only its contact pulse");
        enemy._x=900;leftHp=enemy.hp;ticks(60);check(enemy.hp==leftHp,"brief contact does not grant five seconds of free healing");
        enemy._x=500;enemy.hp=0;world.hero._x=500;world.hero.hp=995;ticks(15);
        check(enemy.hp==0 && world.hero.hp==1000,"serum neither resurrects nor exceeds maximum HP");
        room();NoahMotherEncounter.impact("serum",500,300);world.hero.removeMovieClip();
        var replacement:MovieClip=world.createEmptyMovieClip("hero",2);replacement.hp=500;replacement.hp满血值=1000;
        replacement._x=900;replacement._y=replacement.Z轴坐标=300;replacement.dispatcher=new EventDispatcher();ticks(30);
        check(replacement.hp==500,"same-path replacement outside pool inherits no healing");
        room();enemy=unit(false,false,false);enemy._x=500;enemy._y=enemy.Z轴坐标=300;
        var outside:MovieClip=unit(false,false,false);outside._x=900;outside._y=outside.Z轴坐标=300;
        var edgeX:MovieClip=unit(false,false,false);edgeX._x=747;edgeX._y=edgeX.Z轴坐标=300;
        var outX:MovieClip=unit(false,false,false);outX._x=749;outX._y=outX.Z轴坐标=300;
        var edgeY:MovieClip=unit(false,false,false);edgeY._x=500;edgeY._y=edgeY.Z轴坐标=414;
        var outY:MovieClip=unit(false,false,false);outY._x=500;outY._y=outY.Z轴坐标=416;
        hits=[];var api:Object=BulletQueueProcessor;var old:Function=api.injectHit;
        api.injectHit=function(b:Object,sh:MovieClip,u:MovieClip,x:Number,y:Number,m:Number,legacy:Boolean):Object {
            org.flashNight.arki.scene.NoahMotherEncounterTest.recordHit(b,u);return null;
        };
        NoahMotherEncounter.impact("acid",500,300);
        check(hits.length==4,"reduced ellipse includes inner edges and excludes outer edges");
        check(hits[0].attribute=="巢蚀" && hits[1].friendly && hits[0].power==1500,"persistent acid retains reduced per-hit power and normal settlement");
        check(hits[0].knock==1 && hits[0].noStun===false && hits[0].push==8,"acid allows ordinary knockdown and escape response");
        _root.暂停=true;ticks(90);check(hits.length==4 && NoahMotherEncounter.snapshot().frame==0,"pause freezes ground lifetime and repeated damage");_root.暂停=false;
        ticks(14);check(hits.length==4,"no extra acid hit before half-second interval");
        ticks(1);check(hits.length==8,"half-second pulse rechecks current occupants");
        world.hero._x=900;ticks(15);check(hits.length==11,"leaving acid stops subsequent exposure");
        outside._x=500;ticks(15);check(hits.length==15,"late entrant is hit by an existing acid pool");
        ticks(135);check(hits.length==47 && NoahMotherEncounter.snapshot().pools==0,"six-second acid pool stops after twelve pulses");
        NoahMotherEncounter.impact("acid",500,300);NoahMotherEncounter.impact("acid",700,300);
        check(NoahMotherEncounter.snapshot().pools==1,"same-kind pool replaces instead of stacking");
        NoahMotherEncounter.impact("serum",500,300);check(NoahMotherEncounter.snapshot().pools==2,"at most one area of each kind");
        world.dispatcher.publish("Clear");check(NoahMotherEncounter.snapshot()==null,"victory removes active pools and pulse clocks");
        api.injectHit=old;
    }
    public static function recordHit(b:Object,u:MovieClip):Void {
        hits.push({attribute:b.魔法伤害属性,friendly:b.友军伤害,power:b.子弹威力,name:u._name,
            knock:b.击倒率,noStun:b.不硬直,push:b.水平击退速度});
    }
    private static function combatant(u:MovieClip,player:Boolean,resistance:Number):Void {
        u.hp=u.hp满血值=6000;u._x=500;u._y=u.Z轴坐标=300;u.等级=41;
        u.防御力=1;u.韧性系数=1;u.躲闪率=1;u.remainingImpactForce=0;u.魔法抗性={基础:0,巢蚀:resistance};
        u.createEmptyMovieClip("man",1);u.downCount=0;u.fixturePlayer=player;
        u.shield={absorbDamage:function(n:Number):Number {return n;}};
        u.状态改变=function(state:String):Void {
            this.状态=state;
            if(state=="击倒"){
                this.downCount++;
                // 夹具只提供玩家原生动画使用的无敌标记；不冒充整段玩家时间轴验收。
                if(this.fixturePlayer)this.man.无敌标签=true;
            }
        };
        u.被击移动=function():Void {};
        u.dispatcher.subscribe("hit",combatHit,NoahMotherEncounterTest);
    }
    public static function combatHit(u:MovieClip,sh:MovieClip,b:Object,collision:Object,result:DamageResult):Void {
        var api:Object=ImpactStateHandler;api.handleImpactState(u,b,result,"右",true);
    }
    private static function testRealAcidSettlement():Void {
        room();DamageManagerFactory.init();PinkNoiseEngine.getInstance();
        var oldTimer:Object=_root.帧计时器;_root.帧计时器={当前帧数:100};
        var dodge:Object=DodgeHandler;var oldDodge:Function=dodge.calculateDodgeState;
        dodge.calculateDodgeState=function():String {return "未躲闪";};
        var hero:MovieClip=world.hero;combatant(hero,true,0);
        var enemy:MovieClip=unit(false,false,false);combatant(enemy,false,0);
        var mother:MovieClip=unit(true,false,false);combatant(mother,false,139);
        NoahMotherEncounter.impact("acid",500,300);
        check(hero.hp>=4275 && hero.hp<=4725 && hero.downCount==1,"real first pulse is survivable at 6000 HP and invokes knockdown");
        check(enemy.hp<6000 && mother.hp>5980,"normal mobs take meaningful damage while mother survives");
        var hp:Number=hero.hp;var mobHp:Number=enemy.hp;var hitTime:Number=hero.lastHitTime;
        _root.帧计时器.当前帧数=115;ticks(15);
        check(hero.hp==hp && hero.downCount==1 && hero.lastHitTime==hitTime,"native invincibility flag prevents repeat damage and impact retrigger");
        check(enemy.hp<mobHp,"unprotected enemy accumulates damage on next pulse");
        hero.man.无敌标签=false;hero._x=900;_root.帧计时器.当前帧数=130;ticks(15);
        check(hero.hp==hp && hero.downCount==1,"escaping area stays safe after invincibility ends");
        ticks(135);check(enemy.hp==0 && mother.hp>5700,"persistent exposure clears ordinary enemy while preserving producer");
        dodge.calculateDodgeState=oldDodge;_root.帧计时器=oldTimer;
    }
    private static function testResistance():Void {
        var result:DamageResult=new DamageResult();
        var bullet:Object={伤害类型:"魔法",魔法伤害属性:"巢蚀",破坏力:1500,是否为敌人:true};
        var target:Object={等级:41,魔法抗性:{巢蚀:139,基础:20,蚀:35}};
        UniversalDamageHandle.instance.handleBulletDamage(bullet,{},target,{},result);
        check(Math.abs(target.损伤值-15)<0.001,"production resistance formula gives mothers 99 percent protection");
        bullet.魔法伤害属性="蚀";UniversalDamageHandle.instance.handleBulletDamage(bullet,{},target,{},result);
        check(Math.abs(target.损伤值-975)<0.001,"ordinary corrosive resistance remains independent");
        bullet.魔法伤害属性="巢蚀";delete target.魔法抗性.巢蚀;
        UniversalDamageHandle.instance.handleBulletDamage(bullet,{},target,{},result);
        check(Math.abs(target.损伤值-1200)<0.001,"other units retain standard base-resistance fallback");
    }
    private static function testLifecycle():Void {
        room();unit(false,false,true);var oldWorld:MovieClip=world;
        _root.gameworld=_root.createEmptyMovieClip("replacementWorld",_root.getNextHighestDepth());
        NoahMotherEncounter.tick();check(NoahMotherEncounter.snapshot()==null,"old world cannot keep firing after a transition");
        check(oldWorld.__noahMotherEncounter==undefined,"old world's admission hook removed");
        _root.gameworld.removeMovieClip();room();check(NoahMotherEncounter.snapshot().larvae==0,"reentry has a fresh production budget");
        world.dispatcher.publish("Clear");check(NoahMotherEncounter.snapshot()==null,"victory cancels timers and pending liquid effects");
        room();world.dispatcher.publish("StageFailed");check(NoahMotherEncounter.snapshot()==null,"failure performs the same cleanup");
    }
    public static function recordSound(id:String):Void {sounds.push(id);}
    private static function soundCount(id:String):Number {
        var n:Number=0;for(var i:Number=0;i<sounds.length;i++)if(sounds[i]==id)n++;return n;
    }
    private static function testAudio():Void {
        room();ticks(1);
        check(sounds.length==1 && sounds[0]=="金属刮擦.wav","hoist starts once on first advancing entrance frame");
        _root.暂停=true;ticks(100);
        check(sounds.length==1 && NoahMotherEncounter.snapshot().frame==1,"paused entrance neither advances nor repeats sound");_root.暂停=false;
        ticks(78);check(sounds.length==1,"reveal cry waits for visible entrance pose");
        ticks(1);check(sounds.length==2 && sounds[1]=="克隆怪嘶吼3.wav","reveal cry aligns with entrance frame eighty");
        ticks(250);var kind:String=NoahMotherEncounter.snapshot().kind;
        world.hero._x=900; // 时序夹具避开落点；真实伤害另由专门用例覆盖。
        check(sounds.length==3 && sounds[2]=="blood6.wav","liquid charge has one short organic cue");
        ticks(23);check(sounds.length==3,"expel cue waits until the projectile release frame");
        ticks(1);check(sounds.length==4 && sounds[3]=="blood7.wav","projectile release emits exactly one expel cue");
        ticks(35);check(sounds.length==4,"airborne liquid has no premature landing cue");
        ticks(1);check(sounds.length==5 && sounds[4]==(kind=="acid"?"m1014毒液.wav":"blood5.wav"),"actual landing chooses its liquid-specific cue once");

        room();ticks(80);
        for(var i:Number=0;i<17;i++){
            var u:MovieClip=unit(false,false,false);u._x=500;u._y=u.Z轴坐标=300;u.hp=100;
        }
        sounds=[];NoahMotherEncounter.impact("serum",500,300);
        check(sounds.length==1 && sounds[0]=="blood5.wav","one serum landing cue serves all eighteen occupants");
        _root.暂停=true;ticks(90);check(sounds.length==1,"paused serum never replays its landing cue");_root.暂停=false;
        ticks(180);check(sounds.length==1,"twelve healing pulses and their per-unit effects add no sound spam");
        room();ticks(80);world.hero._x=900;sounds=[];NoahMotherEncounter.impact("acid",500,300);
        check(sounds.length==1 && sounds[0]=="m1014毒液.wav","acid landing has its own existing effect");
        ticks(180);check(sounds.length==1,"acid lifetime and periodic damage do not repeat landing sound");

        room();ticks(151);
        for(i=0;i<9;i++){u=unit(true,true,false);u.hp=0;}
        sounds=[];ticks(1);
        check(sounds.length==1 && sounds[0]=="soundheadexplode.wav","first exhaustion transition emits one rupture cue");
        ticks(200);check(soundCount("soundheadexplode.wav")==1 && NoahMotherEncounter.snapshot().phase==1,"pose changes do not replay the phase rupture");
        world.dispatcher.publish("Clear");sounds=[];ticks(400);
        check(sounds.length==0 && NoahMotherEncounter.snapshot()==null,"scene teardown cannot emit delayed encounter cues");

        room();ticks(164);u=unit(true,true,false);u.hp=0;sounds=[];ticks(25);
        check(NoahMotherEncounter.snapshot().larvae==1 && soundCount("blood6.wav")==1 && soundCount("blood7.wav")==1,"large gene bug keeps charge and actual expel cues");
        room();ticks(164);u=unit(true,true,false);u.hp=0;sounds=[];ticks(1);
        for(i=0;i<17;i++)unit(false,false,false);
        ticks(24);check(NoahMotherEncounter.snapshot().larvae==0 && soundCount("blood7.wav")==0 && soundCount("blood6.wav")==1,"population rejection cannot fake a successful expel sound");

        room();
        for(i=0;i<12;i++){u=unit(true,true,false);u.hp=0;}
        for(i=0;i<6;i++){u=unit(false,false,true);u.hp=0;u.__noahTransformed=true;}
        sounds=[];ticks(1);
        check(sounds.length==2 && sounds[0]=="soundheadexplode.wav" && sounds[1]=="克隆怪嘶吼2.wav","death begins with rupture and final cry once");
        ticks(17);check(sounds.length==2,"chain cue waits for the first falling frame");
        _root.暂停=true;ticks(60);check(sounds.length==2 && NoahMotherEncounter.snapshot().deathFrame==18,"pause also freezes death audio timing");_root.暂停=false;
        ticks(1);check(sounds.length==3 && sounds[2]=="火凤_链条.wav","chain snap coincides with frame nineteen");
        ticks(50);check(sounds.length==3,"well impact waits until the body has disappeared");
        ticks(1);check(sounds.length==4 && sounds[3]=="地震3.wav","well impact occurs once at frame seventy");
        ticks(120);check(sounds.length==4 && NoahMotherEncounter.snapshot().deathFrame==90,"holding final death frame never loops the ending sound");
        room();ticks(1);check(sounds.length==1 && sounds[0]=="金属刮擦.wav","reentry gets its own fresh entrance cue");
        var play:Function=_root.播放音效;delete _root.播放音效;room();ticks(330);
        check(NoahMotherEncounter.snapshot().frame==330,"missing audio entry never blocks the encounter clock");_root.播放音效=play;
    }
    private static function loadArt():Void {
        loaded=_root.createEmptyMovieClip("noahPublishedArt",_root.getNextHighestDepth());
        loader=new MovieClipLoader();listener={};
        listener.onLoadInit=function(mc:MovieClip):Void {org.flashNight.arki.scene.NoahMotherEncounterTest.artLoaded(mc);};
        listener.onLoadError=function(mc:MovieClip,code:String):Void {trace("[FAIL] Noah native art failed: "+code);};
        loader.addListener(listener);loader.loadClip("../flashswf/movies/尸母巢穴巨型尸母.swf",loaded);
    }
    public static function artLoaded(mc:MovieClip):Void {
        check(mc.noahAssetVersion===1 && mc.noahPresentationVersion===3,"published native giant exposes the new control contract");
        mc.noahPose("空闲",1,0,"",0);var first:Number=fingerprint(mc);
        check(mc.noahMotion._totalframes==80 && mc.noahMotion.noahHead!=undefined,"original idle and named head preserved");
        check(mc.noahMotion.noahHead.noahEye0._width>0,"acid eye flame is an actual exported vector");
        mc.noahPose("空闲",1,1,"acid",10);var second:Number=fingerprint(mc);
        check(first!=second,"second damage state changes rendered pixels");
        mc.noahPose("结束",1,2,"",20);var last:Number=fingerprint(mc);
        check(second!=last && mc._width>100,"terminal damage appears before the fall");
        check(mc.noahMotion.noahBody.noahHead.noahEye0._visible===false,"exhausted eyes are extinguished");
        mc.noahPose("喷吐",25,0,"serum",30);
        check(mc.noahMotion._totalframes==66 && mc.noahMotion._currentframe==25,"original spit frame remains usable");
        var kinds:Array=["acidDrop","acidSplash","serumDrop","serumSplash"];
        for(var i:Number=0;i<kinds.length;i++){
            var fx:MovieClip=mc.attachMovie("Noah_"+kinds[i],"probe"+i,200+i);
            check(fx._width>15 && fx._height>15,"native liquid export: "+kinds[i]);fx.removeMovieClip();
        }
        mc.noahPose("空闲",1,0,"",0);mc._xscale=mc._yscale=72;mc._y=120;
        NoahMotherEncounter.teardown();if(world!=null)world.removeMovieClip();
        _root.gameworld=saved.world;_root.控制目标=saved.hero;_root.暂停=saved.pause;
        _root.场景转换中=saved.transition;_root.加载游戏世界人物=saved.spawn;_root.播放音效=saved.sound;
        trace("NoahMotherEncounterTest Tests Passed: "+passed);
        trace("NoahMotherEncounterTest Tests Failed: "+failed);
        trace("NoahMotherEncounterTest Native Asset Loaded: true");
        trace("FocusedTestRunId noah-mother Complete: "+_root.__noahMotherFocusedRunId);
        if(failed>0)throw new Error("NoahMotherEncounterTest failed");
    }
    private static function fingerprint(mc:MovieClip):Number {
        var b:BitmapData=new BitmapData(650,350,true,0);b.draw(mc,new Matrix());var sum:Number=0;
        for(var y:Number=0;y<350;y+=3)for(var x:Number=0;x<650;x+=3)sum=(sum+(b.getPixel32(x,y)>>>0)*(x+y+1))%1000000007;
        b.dispose();return sum;
    }
}
