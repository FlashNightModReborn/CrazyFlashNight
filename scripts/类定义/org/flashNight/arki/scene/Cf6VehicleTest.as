import org.flashNight.arki.scene.*;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.arki.hud.FocusTargetHudService;
import org.flashNight.arki.component.Damage.DamageManagerFactory;
import org.flashNight.arki.component.Shield.AdaptiveShield;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.RespawnEventComponent;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine;
import flash.display.BitmapData;
import flash.geom.Matrix;

/** Native RSL/pipeline suite. Hero initialization and full-game presentation are separate gates. */
class org.flashNight.arki.scene.Cf6VehicleTest {
    private static var passed:Number,failed:Number,frame:Number,phase:Number,age:Number,keyCalls:Number;
    private static var driver:MovieClip,world:MovieClip,hero:MovieClip;
    private static var s:Object,room:Object,keys:Object,oldInput:Function,walk:Function,mode:Function,checkKey:Function;
    private static var pauseLease:String,paused:Object,bossAt:Number,deathAt:Number,shotsBefore:Number;
    private static var hitEvents:Number,killEvents:Number,unknownCalls:Number,fixtureSerial:Number,done:Boolean;
    private static var audioCalls:Object,deathVariants:Object,deathChosen:Object,referenceAt:Number,startedAt:Number;
    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++;else {failed++;trace("[FAIL] Cf6Vehicle: "+label);}
    }
    private static function pixels(clip:MovieClip):Number {
        var b:Object=clip.getBounds(clip),m:Matrix=new Matrix();m.translate(-b.xMin+2,-b.yMin+2);
        var image:BitmapData=new BitmapData(900,700,true,0);image.draw(clip,m);
        var r:Object=image.getColorBoundsRect(0xFF000000,0,false);var result:Number=r.width*r.height;image.dispose();return result;
    }
    public static function runAllTests():Void {
        passed=failed=frame=phase=age=keyCalls=hitEvents=killEvents=unknownCalls=fixtureSerial=0;done=false;
        audioCalls={};deathVariants={};deathChosen={};referenceAt=-1;startedAt=getTimer();
        var inputApi:Object=Cf6VehicleService;oldInput=inputApi.readInput;keys={};
        var controlledInput:Function=function():Object {
            keyCalls++;return {x:(keys[68]===true?1:0)-(keys[65]===true?1:0),
                z:(keys[83]===true?1:0)-(keys[87]===true?1:0),fire:keys[74]===true};
        };
        inputApi.readInput=controlledInput;keys[68]=true;keys[87]=true;keys[74]=true;
        var inputProbe:Object=inputApi.readInput();
        check(inputApi.readInput===controlledInput && inputProbe.x===1 && inputProbe.z===-1 && inputProbe.fire===true,"controlled intent port replaces the ordinary method and returns exact fixture axes");
        keys={};trace("VehicleInputEvidence: controlled_intent; native_key_mapping=source_fixture_only");
        _root.左键=65;_root.右键=68;_root.上键=87;_root.下键=83;_root.A键=74;
        _root.当前关卡名="书中历险-毒刺行动";_root.savePath="cf6.vehicle.fixture";
        _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"historical",slot:_root.savePath,seed:79,startedAt:100,planSeed:79,outcome:"active"}};
        _root.场景转换中=false;_root.暂停=false;PauseManager.install();PauseManager.set(false,"cf6_vehicle_fixture");
        _root.播放音效=function(name:String):Void {audioCalls[name]=(audioCalls[name]|0)+1;};_root.效果=function():Void {};_root.发布消息=function():Void {};
        _root.帧计时器={当前帧数:0};DamageManagerFactory.init();PinkNoiseEngine.getInstance();FactionManager.initialize();BulletQueueProcessor.initialize();
        fresh();
        driver=_root.createEmptyMovieClip("__cf6VehicleDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {try {Cf6VehicleTest.tick();}catch(e) {Cf6VehicleTest.abort(String(e));}};
    }
    private static function fresh():Void {
        Cf6VehicleService.dispose(s);
        if(hero.shield!=undefined) {hero.shield.setOwner(null);delete hero.shield;}
        if(world!=undefined) world.removeMovieClip();
        world=_root.createEmptyMovieClip("__cf6VehicleWorld"+(++fixtureSerial),_root.getNextHighestDepth());_root.gameworld=world;
        world.__stageReturnWorldIdentity={};world.dispatcher=new EventDispatcher();
        var init:Object=Cf6ActorMaskState.prepare(world,world.__stageReturnWorldIdentity,"hero",{});
        hero=world.attachMovie("CF6Vehicle","hero",world.getNextHighestDepth(),init);Cf6ActorMaskState.bind(hero,init);
        hero.hp=hero.hp满血值=1000;hero._x=265.45*1024/600;hero._y=hero.Z轴坐标=352.15*1024/600;
        hero.是否为敌人=false;hero.防御力=1;hero.damageTakenMultiplier=1;hero._visible=true;
        hero.无敌=false;hero.NPC=false;hero.防止无限飞=false;hero._killed=false;
        hero.shield=AdaptiveShield.createDormant("vehicle-fixture-shield");hero.shield.setOwner(hero);
        hero.dispatcher=new EventDispatcher();hero.dispatcher.subscribe("hit",function():Void {hitEvents++;},null);
        hero.dispatcher.subscribe("kill",function():Void {killEvents++;hero._killed=true;},null);
        walk=function():Void {};mode=function():Void {};checkKey=function():Boolean {return true;};
        hero.行走=walk;hero.按键控制攻击模式=mode;hero.按键检测=checkKey;
        hero.createEmptyMovieClip("控制块",1).onEnterFrame=function():Void {};
        _root.控制目标="hero";var manager:Object={currentStage:0,isActive:true,isFailed:false,isFinished:false,gameworld:world};
        var api:Object=StageManager;api.instance=manager;
        room={world:world,owner:world.__stageReturnWorldIdentity,mapId:"A07",stageManager:manager};
        s=Cf6VehicleService.begin(room,Cf6VehicleTestData.spec());age=0;
    }
    private static function fixtureRaider():Void {
        var name:String="fixtureRaider"+(++fixtureSerial);
        var clip:MovieClip=world.attachMovie("CF6VehicleRaider",name,world.getNextHighestDepth());
        clip.__cf6VehicleOwner=s.token;clip.hp=10;clip._x=hero._x+260*s.spec.scale;
        clip._y=hero.Z轴坐标+1.5*s.spec.scale;clip._xscale=clip._yscale=100*s.spec.scale;
        s.actors.push({clip:clip,kind:"raider",generator:-1,identity:name,age:0,resolved:false,closed:false});
    }
    private static function nativeArtChecks():Void {
        var specs:Array=[["CF6VehiclePlayer",29,1803],["CF6VehicleArmoredBoss",209,1813],["CF6VehicleRoad",49,1791],
            ["CF6VehicleRaider",97,612],["CF6VehicleShield",98,629],["CF6VehicleRoadblock",17,627],["CF6VehicleGrenade",61,361],
            ["CF6VehicleBullet",1,356],["CF6VehicleSpark",140,115],["CF6VehicleExplosion",133,391]];
        for(var i:Number=0;i<specs.length;i++) {
            var c:MovieClip=world.attachMovie(specs[i][0],"nativeProbe"+i,world.getNextHighestDepth());
            check(c._totalframes==specs[i][1],"real RSL authored frame count "+specs[i][0]);
            if(specs[i][2]==115 || specs[i][2]==391)c.gotoAndStop(2);
            check(pixels(c)>0,"real RSL nonempty art "+specs[i][0]);c.removeMovieClip();
        }
        check(s.player.p1.p2!==s.player.p1.p4,"redrawn front and rear wheels are independent original timelines");
        check(s.player.p1.p2._totalframes==4 && s.player.p1.p4._totalframes==4,"both wheels preserve four source frames");
    }
    public static function tick():Void {
        if(done)return;frame++;age++;_root.帧计时器.当前帧数=frame;
        if(frame>2400 || getTimer()-startedAt>150000) {abort("native suite timeout phase="+phase+" state="+s.status+" reason="+s.reason);return;}
        if(phase==0) {
            if(s==null) {abort("begin rejected actual known-mask fixture");return;}
            var state:String=Cf6VehicleService.tick(s);
            if(state=="failed") {abort("loading failed "+s.reason);return;}
            if(state!="playing")return;
            check(s.loadingLease===undefined,"loading lease released once assets are ready");
            check(!hero._visible && hero.行走!==walk && hero.按键检测()===false,"real hero hidden with actor-local controls owned");
            nativeArtChecks();keys[68]=true;phase=1;age=0;paused={x:hero._x,wheel:s.player.p1.p2._currentframe};return;
        }
        if(phase==1) {
            Cf6VehicleService.tick(s);
            if(age<12)return;
            check(hero._x>paused.x,"controlled intent moves the actual hero and car");
            check(s.player._x==hero._x && Math.abs(s.player._y-hero.Z轴坐标)<=1/20,"car follows authoritative actor coordinates within one world twip");
            check(s.generators.length==3 && s.generators[0].active!=null && s.generators[1].active!=null && s.generators[2].active!=null,"three source generators produce their one concurrent actor at frame ten");
            check(s.generators[0].remaining==200 && s.generators[1].remaining==15 && s.generators[2].remaining==200,"source death budgets are not an invented 415-kill target");
            check(s.actors[0].clip.hp==100 && s.generators[0].active.clip.hp==10 && s.generators[1].active.clip.hp==200,"initial and generated actor health retain different source values");
            keys[68]=false;keys[74]=true;Cf6VehicleService.tick(s);
            var flight:Object=s.projectiles[0];
            check(flight!=null && Math.abs(flight.dx*flight.dx+flight.dy*flight.dy-400)<0.00001,"original spread changes direction while preserving speed twenty");
            check(Math.abs(flight.dy)<=20*Math.sin(4*3.14/180)+0.00001,"original random-five spread stays within four degrees");
            check(flight.clip._totalframes==1 && flight.clip.p3._totalframes==14,"projectile consumes original nested fourteen-frame body");
            paused={x:hero._x,road:s.road._currentframe,shots:s.shots,clock:s.rules.frame,keyCalls:keyCalls,audio:audioCalls['CF6Vehicle_1169.mp3']};
            pauseLease=PauseManager.lease(true,"foreign_panel");phase=2;age=0;return;
        }
        if(phase==2) {
            Cf6VehicleService.tick(s);if(age<8)return;
            check(s.rules.frame==paused.clock && s.road._currentframe==paused.road,"external pause freezes encounter and original road timeline");
            check(s.shots==paused.shots && keyCalls==paused.keyCalls,"pause neither polls input nor spends fire clock");
            check(hero._x==paused.x,"paused current hero stays fixed");PauseManager.releaseLease(pauseLease);pauseLease=null;
            check(audioCalls['CF6Vehicle_1169.mp3']==paused.audio,"external pause suppresses both barrel audio calls");
            keys[74]=false;
            var generator:Object=s.generators[0],oldRow:Object=generator.active;
            var before:Number=s.rules.roadKills;
            Cf6VehicleCombat.hitRoad(s,oldRow,true);
            check(generator.remaining==199 && generator.active==null && s.rules.roadKills==before+1,"actual knockdown consumes one death budget and releases one concurrency slot");
            check(!Cf6VehicleCombat.hitRoad(s,oldRow,true) && generator.remaining==199,"same terminal actor cannot release or count twice");
            while(s.age<32)Cf6VehicleService.tick(s);
            check(generator.active==null,"source generator does not refill before next 23-frame cycle");
            Cf6VehicleService.tick(s);
            check(generator.active!=null && generator.active!==oldRow && generator.remaining==199,"next source cycle refills exactly one actor without consuming another budget");
            check(s.projectiles.length==0,"source projectile body expires without a one-hundred-frame substitute");
            var escapeRow:Object=s.generators[1].active,killBeforeEscape:Number=s.rules.roadKills;
            escapeRow.clip._x=(s.data.escape[2]-1)*s.spec.scale;Cf6VehicleService.tick(s);
            check(escapeRow.closed && s.generators[1].active==null,"actual disappearance marker releases the exact generator slot");
            check(s.rules.roadKills==killBeforeEscape && s.generators[1].remaining==15,"escaping obstacle neither advances kills nor consumes a death budget");
            var distant:MovieClip=world.attachMovie("CF6VehicleBullet","distanceProbe",world.getNextHighestDepth());distant.__cf6VehicleOwner=s.token;
            var distantRow:Object={clip:distant,x:hero._x/s.spec.scale+801,y:hero._y/s.spec.scale-801,dx:20,dy:0,age:0,closed:false};s.projectiles.push(distantRow);
            Cf6VehicleCombat.projectiles(s);check(distantRow.closed,"original eight-hundred-distance guard retires out-of-range bullet independently of walls");
            check(Cf6VehicleCombat.hitTime([0,0,0,0],0,0,10,10,[0,8,2,10],0,0,0,0)>1,"continuous collision rejects a diagonal broad-box corner false hit");
            check(Cf6VehicleCombat.hitTime([0,0,0,0],0,0,20,0,[0,-1,1,1],15,0,5,0)<=1,"relative-motion collision catches fast opposed projectile and actor crossing");
            Cf6VehicleActorAdapter.move(s.actorAdapter,-10000,-10000,s.spec.scale,s.data.player,s.data.walls);
            check(hero._x+s.data.player[0]*s.spec.scale>=s.data.walls[2][2]*s.spec.scale-1/20,"car left footprint respects original wall within one world twip");
            check(hero._y+s.data.player[1]*s.spec.scale>=s.data.walls[0][3]*s.spec.scale-1/20,"car top footprint respects original wall within one world twip");
            Cf6VehicleActorAdapter.move(s.actorAdapter,10000,10000,s.spec.scale,s.data.player,s.data.walls);
            check(hero._x+s.data.player[2]*s.spec.scale<=s.data.walls[3][0]*s.spec.scale+1/20,"car right footprint respects original wall within one world twip");
            check(hero._y+s.data.player[3]*s.spec.scale<=s.data.walls[1][1]*s.spec.scale+1/20,"car bottom footprint respects original wall within one world twip");
            hero._x=265.45*s.spec.scale;hero._y=hero.Z轴坐标=352.15*s.spec.scale;
            fixtureRaider();
            var hundredRow:Object=s.actors[s.actors.length-1];hundredRow.clip.hp=100;
            var beforeHundred:Number=s.rules.roadKills;
            Cf6VehicleCombat.hitRoad(s,hundredRow,false);
            check(hundredRow.clip.hp==80 && hundredRow.resolved && hundredRow.clip._currentframe==77 && s.rules.roadKills==beforeHundred+1,"source 612 dies on one bullet even with eighty HP remaining");
            var shieldClip:MovieClip=world.attachMovie("CF6VehicleShield","shieldHealthBoundary",world.getNextHighestDepth());
            shieldClip.__cf6VehicleOwner=s.token;shieldClip.hp=300;
            var shieldRow:Object={clip:shieldClip,kind:"shield",generator:-1,identity:"shieldHealthBoundary",age:0,resolved:false,closed:false};s.actors.push(shieldRow);
            var beforeShield:Number=s.rules.roadKills;
            for(var hit:Number=0;hit<16;hit++)Cf6VehicleCombat.hitRoad(s,shieldRow,false);
            check(shieldClip.hp==-20 && !shieldRow.resolved && !shieldRow.closed && shieldClip._currentframe==50 && s.rules.roadKills==beforeShield,"source 629 keeps its pain branch below zero HP without a gun-death event");
            for(var i:Number=0;i<s.actors.length;i++)Cf6VehicleCombat.retire(s,s.actors[i]);s.actors=[];
            for(i=0;i<s.generators.length;i++)s.generators[i].remaining=0;
            s.rules.roadKills=0;s.rules.roadEvents={};keys[74]=true;
            phase=3;age=0;return;
        }
        if(phase==3) {
            if(age%8==1 && s.rules.phase=="road")fixtureRaider();
            Cf6VehicleService.tick(s);
            for(var observed:Number=0;observed<s.actors.length;observed++) {
                var observedRow:Object=s.actors[observed];
                if(observedRow.resolved && observedRow.knockdown!==true && observedRow.variant!==undefined)
                    deathChosen[observedRow.variant]=true;
                if(observedRow.resolved && !observedRow.variantPending && observedRow.clip.p1.__cf6SourceId==611) {
                    var nativeFrame:Number=observedRow.clip.p1._currentframe;
                    deathVariants[nativeFrame>=78?"a2":(nativeFrame>=32?"a1":"a0")]=true;
                }
            }
            if(s.status!="playing") {abort("road failed "+s.reason);return;}
            if(s.rules.phase!="boss-intro")return;
            check(s.rules.roadKills==30,"thirty actual source road terminal collisions open boss intro");
            check(s.shots>0 && s.boss==undefined,"physical dual-gun projectiles precede boss spawn");
            trace("VehicleDeathBranches: chosen="+deathChosen[1]+","+deathChosen[32]+","+deathChosen[78]
                +" observed="+deathVariants.a0+","+deathVariants.a1+","+deathVariants.a2);
            check(deathVariants.a0 && deathVariants.a1 && deathVariants.a2,"actual nested raider death playback reaches all three source branches");
            paused={keyCalls:keyCalls,shots:s.shots};_root.__vehicleIntroClock.gotoAndStop(1);_root.__vehicleIntroClock.play();referenceAt=-1;phase=4;age=0;return;
        }
        if(phase==4) {
            Cf6VehicleService.tick(s);
            if(_root.__vehicleIntroClock._currentframe==59 && referenceAt<0)referenceAt=age;
            if(s.rules.phase!="boss")return;
            check(age==58,"source helper starts on frame one and reaches fifty-nine after fifty-eight advances");
            check(referenceAt==age,"service intro matches independent real Flash play-from-one timeline");
            check(keyCalls==paused.keyCalls && s.shots==paused.shots,"intro freezes car fire and input");
            check(s.boss._parent===world && world[s.boss._name]===s.boss && s.boss.hp==5000,"boss is direct world actor with one fixed HP authority");
            check(s.hudLease!=null && FocusTargetHudService.snapshot()!=null,"actual boss HUD binds owned actor");
            bossAt=frame;phase=5;age=0;return;
        }
        if(phase==5) {
            Cf6VehicleService.tick(s);
            if(age==18)check(s.rules.bossFrame==19 && s.grenades.length==1,"first native boss throw is source frame nineteen, eighteen advances after birth");
            // The complete route remains deterministic after proving one real hit;
            // subsequent grenade attempts exercise the native invulnerability gate.
            if(s.grenadeHits>0)hero.无敌=true;
            if(s.status!="playing") {abort("boss failed "+s.reason+" hp="+hero.hp);return;}
            if(s.rules.phase!="boss-death")return;
            check(s.boss.hp==0 && s.bossHits==250,"fixed source bullets need exactly 250 accepted hits against 5000 HP");
            check(s.rules.bossFrame==121,"authoritative boss death enters original frame 121");
            check(s.grenadeHits>0 && hero.hp<1000 && hitEvents>0,"authored grenade collision reaches actual native hero damage pipeline");
            check(audioCalls['CF6Vehicle_1169.mp3']==s.shots,"each physical barrel shot routes the exact extracted original gun sound");
            deathAt=frame;phase=6;age=0;return;
        }
        if(phase==6) {
            Cf6VehicleService.tick(s);
            if(s.rules.phase!="tail")return;
            check(s.rules.bossFrame==208 && frame-deathAt==87,"original boss departure reaches 208 before tail");
            check(s.boss==null && s.hudLease==null,"boss departure releases exact HUD and actor");
            var counts:Object={raider:0,shield:0,obstacle:0};for(var j:Number=0;j<s.actors.length;j++)counts[s.actors[j].kind]++;
            check(counts.raider==2 && counts.shield==5 && counts.obstacle==2,"tail uses all nine source placements");
            check(audioCalls['CF6_0915.mp3']>0 && audioCalls['CF6_1009.mp3']>=3,"boss departure and grenade animation route original death and explosion cues");
            phase=7;age=0;return;
        }
        if(phase==7) {
            Cf6VehicleService.tick(s);
            if(s.status!="complete")return;
            check(s.rules.phase=="complete" && s.tailX<s.data.endpoint.x,"only actual moving tail endpoint completes");
            var x:Number=hero._x;keys[68]=true;var count:Number=keyCalls;
            check(Cf6VehicleService.tick(s)=="complete" && hero._x==x && keyCalls==count,"complete remains stable and input locked");
            check(!hero._visible && hero.行走!==walk && s.player._parent===world,"complete preserves car until real teardown");
            Cf6VehicleService.dispose(s);
            check(hero._visible && hero.行走===walk && hero.按键控制攻击模式===mode && hero.按键检测===checkKey,"dispose restores exactly owned actor slots");
            check(world.__cf6VehicleSession===undefined,"teardown clears only exact room session");
            var high:Object=Cf6VehicleRules.create(Cf6VehicleTestData.spec().rules,{},1000000000,8,4);
            check(high!=null && high.health==1000000000,"valid current hero HP is not capped by coordinate validation");
            fresh();keys={};phase=8;age=0;return;
        }
        if(phase==8) {
            if(Cf6VehicleService.tick(s)!="playing")return;
            s.boss=world.attachMovie("CF6VehicleArmoredBoss","damageBoss",world.getNextHighestDepth());s.boss.__cf6VehicleOwner=s.token;
            s.boss.dispatcher=new EventDispatcher();s.boss.伤害加成=0;s.boss.是否为敌人=true;
            s.boss.hp=4200;s.boss.hp满血值=5000;s.rules.phase="boss";s.rules.bossFrame=37;s.rules.roadKills=30;
            s.hudIdentity={};s.boss.__cf6HudIdentity=s.hudIdentity;
            s.hudLease=FocusTargetHudService.bind(world,s.owner,s.boss,"__cf6HudIdentity",s.hudIdentity,"boss","装甲战车");
            StageRunSession.testOnlyReset();check(StageRunSession.begin("书中历险-毒刺行动","fixture",undefined),"real run authority starts isolated revival lifecycle");
            var grenade:MovieClip=world.attachMovie("CF6VehicleGrenade","damageGrenade",world.getNextHighestDepth());grenade.__cf6VehicleOwner=s.token;
            var g:Object={clip:grenade,attempted:false};var hp:Number=hero.hp;
            check(Cf6VehicleCombat.damageHero(s,g) && hero.hp==hp-150,"source 30 of 200 maps once into current hero maximum HP");
            check(!Cf6VehicleCombat.damageHero(s,g) && hero.hp==hp-150,"accepted grenade event is never replayed");
            hero.hp=100;hero._killed=false;g={clip:grenade,attempted:false};var kills:Number=killEvents;
            check(Cf6VehicleCombat.damageHero(s,g) && hero.hp==0 && killEvents==kills+1,"native damage settles lethal HP and publishes one kill");
            StageRunSession.onHeroDeath();var seedBefore:Number=s.rng;
            check(Cf6VehicleService.tick(s)=="dead" && room.stageManager.isFailed===false,"ordinary hero death suspends car encounter without StageFailed");
            var life:Object=StageRunSession.testOnlySnapshot();
            check(life.life=="dead" && life.outcome=="active","actual run life and outcome remain orthogonal during death");
            var deadFrame:Number=s.rules.bossFrame,deadAge:Number=s.age,deadProjectiles:Number=s.projectiles.length;
            for(var waitDead:Number=0;waitDead<10;waitDead++)Cf6VehicleService.tick(s);
            check(s.status=="dead" && s.rules.bossFrame==deadFrame && s.age==deadAge && s.projectiles.length==deadProjectiles,"dead state freezes existing encounter and ordnance clocks");
            check(s.loadingLease===undefined && hero.行走===walk && !hero._visible,"death returns actor controls and releases loading pause while retaining only car presentation");
            check(s.hudLease==null && s.boss.hp==4200 && s.rules.roadKills==30 && s.rng==seedBefore,"death clears exact HUD without resetting boss, road progression or seed");
            var revivedWalk:Function=function():Void {};
            hero.动画完毕=function():Void {hero.行走=revivedWalk;};
            RespawnEventComponent.onHeroRespawn(hero);
            check(hero.hp==hero.hp满血值 && !hero._killed && StageRunSession.testOnlySnapshot().life=="alive","actual RespawnEventComponent restores same actor and run life");
            check(Cf6VehicleService.tick(s)=="playing" && s.actorAdapter.hero===hero && !hero._visible,"same-world actual respawn reacquires car presentation without replacing hero");
            check(s.actorAdapter.walk===revivedWalk && s.hudLease!=null && s.boss.hp==4200 && s.rules.bossFrame==deadFrame && s.rules.roadKills==30 && s.rng==seedBefore,"resume captures fresh callbacks and restores HUD with unchanged encounter identity");
            check(!Cf6VehicleCombat.damageHero(s,g) && hero.hp==hero.hp满血值,"revival does not clear already-attempted grenade identity");
            grenade.removeMovieClip();Cf6VehicleService.dispose(s);
            check(hero.行走===revivedWalk,"post-revival teardown restores the fresh native callback, not stale pre-death callback");
            fresh();phase=9;age=0;return;
        }
        if(phase==9) {
            if(Cf6VehicleService.tick(s)!="playing")return;
            var foreign:Function=function():Void {};hero.行走=foreign;
            check(Cf6VehicleService.tick(s)=="cancelled","foreign actor control ownership cancels this session");
            check(hero.行走===foreign,"CAS release never overwrites foreign control function");
            var invalid:Object=Cf6VehicleTestData.spec();invalid.assetUrl="foreign.swf";
            check(Cf6VehicleService.begin(room,invalid)==null,"closed spec rejects foreign asset URL without side effects");
            check(Cf6VehicleService.begin({world:world,owner:room.owner,mapId:"A07",stageManager:{}},Cf6VehicleTestData.spec())==null && hero._visible,"foreign stage manager is rejected before acquiring actor or pause ownership");
            fresh();phase=10;age=0;return;
        }
        if(phase==10) {
            if(Cf6VehicleService.tick(s)!="playing")return;
            var old:MovieClip=hero;var other:MovieClip=_root.createEmptyMovieClip("foreignWorld",_root.getNextHighestDepth());_root.gameworld=other;
            check(Cf6VehicleService.tick(s)=="cancelled" && other.__cf6VehicleSession===undefined,"world replacement cancels without touching foreign world");
            check(old.行走===walk && old._visible,"old exact actor restores after world replacement");
            other.removeMovieClip();_root.gameworld=world;fresh();phase=11;age=0;return;
        }
        if(phase==11) {
            if(Cf6VehicleService.tick(s)!="playing")return;
            s.boss=world.attachMovie("CF6VehicleArmoredBoss","unknownBoss",world.getNextHighestDepth());s.boss.__cf6VehicleOwner=s.token;
            s.boss.dispatcher=new EventDispatcher();s.boss.伤害加成=0;s.boss.是否为敌人=true;
            var unknownGrenade:MovieClip=world.attachMovie("CF6VehicleGrenade","unknownGrenade",world.getNextHighestDepth());unknownGrenade.__cf6VehicleOwner=s.token;
            var originalPublish:Function=hero.dispatcher.publish;
            hero.dispatcher.publish=function():Void {unknownCalls++;throw new Error("fixture post-damage delivery unknown");};
            var unknown:Object={clip:unknownGrenade,attempted:false};var beforeUnknown:Number=hero.hp;
            check(!Cf6VehicleCombat.damageHero(s,unknown) && hero.hp==beforeUnknown-150 && unknownCalls==1,"post-damage exception preserves unknown outcome instead of pretending no HP debit");
            check(!Cf6VehicleCombat.damageHero(s,unknown) && hero.hp==beforeUnknown-150 && unknownCalls==1,"unknown grenade outcome never replays the accepted debit");
            hero.dispatcher.publish=originalPublish;
            check(Cf6VehicleService.tick(s)=="failed" && s.reason=="grenade-delivery-unknown","unknown consumer outcome stops encounter advancement");
            unknownGrenade.removeMovieClip();finish();
        }
    }
    public static function abort(reason:String):Void {check(false,reason);finish();}
    private static function finish():Void {
        if(done)return;done=true;Cf6VehicleService.dispose(s);if(pauseLease!=null)PauseManager.releaseLease(pauseLease);
        if(hero.shield!=undefined) {hero.shield.setOwner(null);delete hero.shield;}
        StageRunSession.testOnlyReset();
        var api:Object=Cf6VehicleService;api.readInput=oldInput;if(driver!=undefined)driver.removeMovieClip();
        trace("Cf6VehicleTest Tests Passed: "+passed);trace("Cf6VehicleTest Tests Failed: "+failed);
        if(typeof _root.cf6VehicleTestComplete=="function")_root.cf6VehicleTestComplete();
    }
}
