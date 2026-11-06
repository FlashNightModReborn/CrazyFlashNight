import org.flashNight.arki.scene.*;
import org.flashNight.arki.unit.Action.Melee.Cf6SoldierAssetTest;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.arki.spatial.move.Mover;
import org.flashNight.neur.Event.EventDispatcher;

/** Real RSL actors/equipment/core commits. Emission and observations are bounded
 * fixtures; real projectile/partner/map gameplay is verified in separate runs. */
class org.flashNight.arki.scene.Cf6FixedSoldierNativeTest {
    private static var passed:Number,failed:Number,ticks:Number,phase:Number,cursor:Number,age:Number;
    private static var world:MovieClip,driver:MovieClip,xml:XML,current:MovieClip;
    private static var config:Object,parameters:Object,metadata:Array,batch:Array,scenarios:Array;
    private static var files:Array,mods:Array,lifecycles:Array,emissions:Array;
    private static var fileIndex:Number,spawned:Number,completed:Number,baseInitializer:Function;
    private static var finished:Boolean,currentScenario:Object,partner:MovieClip,externalActor:MovieClip;
    private static var preparedHandler:Function;
    private static var savedEnemyProperties:Object,poseLinks:Object;
    public static function prepareWorld(handler:Function):Void {preparedHandler=handler;runAllTests();}
    public static function preparationFailures():Number {return failed;}
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[FAIL] Cf6FixedSoldierNativeTest "+label);}
    }
    private static function values(value):Array {return value instanceof Array?value:value==null?[]:[value];}
    public static function runAllTests():Void {
        passed=failed=ticks=phase=cursor=age=spawned=completed=fileIndex=0;finished=false;
        batch=[];mods=[];lifecycles=[];emissions=[];poseLinks={};savedEnemyProperties=_root.敌人属性表;
        config=Cf6FixedActionsFixture.config();metadata=Cf6FixedActionsFixture.metadata();parameters={};
        var groups:Array=Cf6FixedRosterFixture.groups();
        for(var g:Number=0;g<groups.length;g++)for(var i:Number=0;i<groups[g].Quantity;i++){
            var init:Object={};Cf6SoldierRoster.prepare(groups[g],i,init);parameters[init.cf6UnitIdentity]=init;
        }
        trace("[CF6_FIXED_NATIVE_BEGIN] exact equipment materialization; controlled emission recorder");
        Cf6SoldierAssetTest.prepareWorld(prepared);
    }
    private static function prepared(library:MovieClip):Void {
        check(Cf6SoldierAssetTest.preparationFailures()==0,"shared fixture facades and initial item catalogs");
        world=library;files=Cf6FixedActionsFixture.catalogFiles();
        files.push({kind:"enemyProperties",url:"../data/enemy_properties/CF6重制敌人.xml"});
        loadNext();
    }
    private static function loadNext():Void {
        if(fileIndex>=files.length){catalogReady();return;}
        xml=new XML();xml.ignoreWhite=true;
        xml.onLoad=function(ok:Boolean):Void {Cf6FixedSoldierNativeTest.loadedCatalog(ok,this);};
        xml.load(files[fileIndex].url);
    }
    private static function loadedCatalog(ok:Boolean,document:XML):Void {
        var row:Object=files[fileIndex];check(ok,"catalog "+row.url);
        if(!ok){finish();return;}
        var data:Object=XMLParser.parseXMLNode(document.firstChild);
        if(row.kind=="items"){
            var items:Array=values(data.item);
            for(var i:Number=0;i<items.length;i++){
                var item:Object=items[i];ItemUtil.itemDataDict[item.name]=item;
                if(item.type=="武器" || item.type=="防具")ItemUtil.equipmentDict[item.name]=true;
            }
        }else if(row.kind=="enemyProperties")_root.敌人属性表=data;
        else if(row.kind=="mods")mods=mods.concat(values(data.mod));
        else EquipmentUtil.loadEquipmentConfig(data);
        fileIndex++;loadNext();
    }
    private static function catalogReady():Void {
        EquipmentUtil.loadModData(mods);_root.cf6InstallNativeEquipmentLifecycle();
        check(typeof _root.装备生命周期函数.G1111初始化=="function","canonical G1111 lifecycle loaded");
        check(EquipmentUtil.modDict["M203榴弹发射器"]!=null,"canonical structural mods loaded");
        // Imported loading anchors contain authored preview animations. Once
        // their definitions are loaded, retire those previews (including camera
        // shaking explosions); actual test actors retain the shared exports.
        for(var anchorIndex:Number=0;anchorIndex<_root.cf6NativeRslAnchorCount;anchorIndex++){
            var anchor:MovieClip=_root["source"+anchorIndex];
            if(anchor!=null){anchor.swapDepths(_root.getNextHighestDepth());anchor.removeMovieClip();}
        }
        _root.按键输入检测=function():Boolean {return false;};
        _root.帧计时器.taskManager={addLifecycleTask:function(unit:Object,label:String,fn:Function,delay:Number,args:Array):Number {
            Cf6FixedSoldierNativeTest.lifecycles.push({unit:unit,version:unit.version,label:label,fn:fn,args:args});
            return Cf6FixedSoldierNativeTest.lifecycles.length;
        }};
        _root.帧计时器.移除生命周期任务=function(unit:Object,label:String):Void {};
        baseInitializer=_root.初始化敌人模板;
        _root.初始化敌人模板=function():Void {
            this.fixtureFixed=true;this.fixtureTacticalModern=true;this.fixtureCompletion=true;
            Cf6FixedSoldierNativeTest.baseInitializer.call(this);
            this.移动=function(direction:String,amount:Number):Void {Mover.move2D(this,direction,amount);};
        };
        _root.子弹区域shoot传递=recordEmission;
        if(_root.cf6RealProjectile===true)Cf6FixedProjectileHarness.install();
        Mover.init();resetWorld("A09");
        if(preparedHandler!=null){
            var ready:Function=preparedHandler;preparedHandler=null;ready(world);return;
        }
        driver=_root.createEmptyMovieClip("cf6FixedNativeDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {Cf6FixedSoldierNativeTest.tick();};
        phase=1;cursor=0;age=0;
        if(_root.cf6ProjectileLifetimeOnly===true)beginScenarios();
    }
    private static function rectangle(parent:MovieClip,name:String,x:Number,y:Number,w:Number,h:Number):MovieClip {
        var mc:MovieClip=parent.createEmptyMovieClip(name,parent.getNextHighestDepth());
        mc.beginFill(0x5DAED6,80);mc.moveTo(x,y);mc.lineTo(x+w,y);mc.lineTo(x+w,y+h);mc.lineTo(x,y+h);mc.lineTo(x,y);mc.endFill();return mc;
    }
    private static function resetWorld(mapId:String):Void {
        if(world!=null)world.removeMovieClip();
        world=_root.createEmptyMovieClip("cf6FixedWorld"+ticks,_root.getNextHighestDepth());
        _root.gameworld=world;world.子弹区域=world;
        world.createEmptyMovieClip("deadbody",world.getNextHighestDepth()).layers=[null,null,{}];
        _root.collisionLayer=rectangle(world,"fixtureCollision",-40,-40,20,600);
        _root.collisionLayer._visible=false;_root.Xmin=0;_root.Xmax=3000;_root.Ymin=180;_root.Ymax=520;
        org.flashNight.gesh.depth.DepthManager.instance=new org.flashNight.gesh.depth.DepthManager(world);
        check(Cf6SoldierActions.bindWorld(world,StageReturnFlow.worldIdentity(world),config,mapId),"bind isolated native world "+mapId);
        lifecycles=[];
        if(_root.cf6RealProjectile===true)Cf6FixedProjectileHarness.beginWorld(world);
    }
    private static function makeRecord():Object {
        return {contacts:0,bashes:0,grenades:0,explosions:0,shots:0,stabs:0,done:0,deathChecks:0,removed:false,physics:0,
            landings:0,deaths:0,powerOk:true,areaOk:true,contractOk:true,muzzleOk:true,shotFrames:"",shotTicks:[],
            sidearmShots:0,sidearmTicks:[],sidearmFrames:"",ammoBefore:0,slotShots:{长枪:0,手枪:0,手枪2:0}};
    }
    private static function spawn(row:Object):MovieClip {
        var init:Object=ObjectUtil.clone(parameters[row.identity]);
        init.cf6BirthIdentity={};init.cf6BirthX=200;init.cf6BirthZ=300;init._x=200;init._y=300;
        init.兵种=row.linkage;init.等级=row.level;init.fixtureFixed=true;init.fixtureFullProductionInit=true;
        init.fixtureRecord=makeRecord();init.特种兵主动架盾=false;init.特种兵避弹=false;
        return world.attachMovie(row.linkage,"fixedActor"+spawned++,world.getNextHighestDepth(),init);
    }
    private static function expectedWeapon(raw:Object):Object {
        if(typeof raw=="object")return raw;
        var parts:Array=String(raw).split("#");return {name:parts[0],value:{level:Number(parts[1]),mods:parts[3]==""?[]:parts[3].split(",")}};
    }
    private static function validateActor(unit:MovieClip,row:Object):Void {
        check(unit!=null && unit.cf6FixedError==undefined && unit.cf6ActionState!=null,"native fixed adapter "+row.identity+" "+unit.cf6FixedError);
        check(unit.cf6UnitIdentity==row.identity && unit.soldierPhase==row.phase && unit.等级==row.level,"identity/phase/level "+row.identity);
        var p:Object=parameters[row.identity];
        for(var i:Number=0;i<3;i++){
            var slot:String=i==0?"长枪":i==1?"手枪":"手枪2";
            if(p[slot]==null)continue;
            var expected:Object=expectedWeapon(p[slot]),actual:Object=unit[slot];
            check(actual.name==expected.name && actual.value.level==expected.value.level,"resolved name/enhancement "+row.identity+" "+slot);
            check(actual.value.mods instanceof Array && actual.value.mods.join(",")==expected.value.mods.join(","),"exact mods "+row.identity+" "+slot);
            check(unit[slot+"属性"].capacity>0 && unit[slot+"属性"].interval>0,"finite weapon runtime "+row.identity+" "+slot);
        }
        var expectedLong:Object=expectedWeapon(p.长枪);
        var skinKey:String=ItemUtil.itemDataDict[expectedLong.name].data.dressup;
        var holder:MovieClip=unit.man.枪.枪,skin:MovieClip=unit.长枪_引用;
        check(skinKey!=null && unit.长枪_装扮===skinKey && skin!=null && skin===holder.装扮
            && skin.枪口位置._parent===skin,"exact equipped long-gun art and real muzzle "+row.identity+" "+expectedLong.name);
        trace("[CF6_FIELDED_PRIMARY] "+row.identity+" gun="+expectedLong.name+" level="+unit.长枪.value.level
            +" skin="+unit.长枪_装扮+" attached="+(skin!=null && skin===holder.装扮)+" muzzle="+(skin.枪口位置._parent===skin));
        if(p.cf6G1111FixedMode!==undefined){
            check(typeof unit.长枪.value.isRocketMode=="boolean" && unit.长枪.value.isRocketMode===p.cf6G1111FixedMode,"actual G1111 mode "+row.identity);
            var artFrame:Number=unit.长枪_引用._currentframe;
            check(p.cf6G1111FixedMode?artFrame>=31 && artFrame<=45:artFrame>=1 && artFrame<=15,
                "actual mounted G1111 timeline matches its authored mode "+row.identity+" frame="+artFrame);
            check(unit.__cf6G1111!=null && unit.__cf6G1111.cf6Weapon===unit.长枪,"G1111 lifecycle bound to actual item "+row.identity);
        }
        check(unit.手枪==null || unit.手枪.value!==unit.手枪2.value,"independent real pistol objects "+row.identity);
        if(p.特种兵副武器===true)check(unit.长枪副武器配置!=null,"actual underbarrel runtime configured "+row.identity);
        check(unit.dispatcher!=null && !unit.dispatcher.isDestroyed(),"real lifecycle dispatcher remains active "+row.identity);
        var boss:Boolean=unit.soldierIsInstructor===true;
        check(unit.魔法抗性[boss?"首领":"精英"]==(boss?20:15),"real XML classification survives native equipment initialization "+row.identity);
        check(unit.魔法抗性[boss?"精英":"首领"]==undefined,"elite and boss classifications remain distinct "+row.identity);
        if(phase==1 && poseLinks[row.linkage]!==true){poseLinks[row.linkage]=true;verifyRunningFacing(unit,row.linkage);}
    }
    private static function verifyRunningFacing(unit:MovieClip,linkage:String):Void {
        var oldNav:Function=unit.cf6NavWaypoint,oldObservation:Object=unit.cf6Observation;
        var oldTarget:String=unit.攻击目标;
        var target:MovieClip=world.createEmptyMovieClip("poseTarget"+spawned,world.getNextHighestDepth());
        target.hp=100;target._y=target.Z轴坐标=300;
        unit.攻击目标=target._name;unit.cf6Observation={interrupted:false,controlled:false,targetValid:true,visible:true};
        unit.cf6NavWaypoint=function():Object {return {x:this.fixturePoseGoalX,z:300};};
        var clock:Number=unit.soldierClock,ammo:Number=unit.长枪.value.shot;
        for(var side:Number=-1;side<2;side+=2){
            unit._x=800;unit._y=unit.Z轴坐标=300;target._x=800-side*600;
            unit.fixturePoseGoalX=800+side*300;unit.cf6FixedTrack(false);
            check((unit._x-800)*side>0 && unit.方向==(side<0?"右":"左") && unit._xscale*side<0,
                "native running preserves target-facing AI and root transform "+linkage+" "+side);
            check(unit.状态=="长枪跑" && unit._xscale*unit.man._xscale*side>0 && unit.man._x<0,
                "native running body and pivot face actual detour travel "+linkage+" "+side);
            unit._x=800;unit._y=unit.Z轴坐标=300;unit.fixturePoseGoalX=800-side*300;
            unit.cf6FixedTrack(false);
            check(unit.状态=="长枪跑" && unit.man._xscale>0 && unit.man._x>0,
                "same native run timeline restores target-facing body "+linkage+" "+side);
            unit._x=800;unit._y=unit.Z轴坐标=300;unit.fixturePoseGoalX=800+side*80;
            unit.cf6FixedTrack(false);
            check((unit._x-800)*side>0 && unit.方向==(side<0?"右":"左") && unit.状态=="长枪行走" && unit.man._xscale>0 && unit.man._x>0,
                "native backward walking retains target-facing pose "+linkage+" "+side);
        }
        check(unit.soldierClock==clock && unit.长枪.value.shot==ammo,"presentation checks do not advance combat clock or fire "+linkage);
        unit.cf6NavWaypoint=oldNav;unit.cf6Observation=oldObservation;unit.攻击目标=oldTarget;
        delete unit.fixturePoseGoalX;target.removeMovieClip();
    }
    private static function recordEmission(props:Object):Object {
        var unit:MovieClip=_root.gameworld[props.发射者];
        var actualBit:Number=unit.cf6CurrentFireBit;
        if(actualBit==0 && unit.cf6ActionState.variant=="grenade" && props.cf6DamageGroup.born==0)actualBit=16;
        if(unit.cf6ActionState!=null && actualBit>0){
            var s:Object=unit.cf6ActionState;
            emissions.push({identity:unit.cf6UnitIdentity,frame:Cf6SoldierActions.now(),cycle:s.cycle,phase:unit.soldierPhase,
                bit:actualBit,split:props.霰弹值,type:props.子弹种类,stage:s.index});
            check(props.cf6DamageGroup!=null,"actual core binds each committed emission");
            check(isFinite(props.shootX) && isFinite(props.shootY) && isFinite(props.shootZ),"actual native muzzle transform");
        }
        if(_root.cf6RealProjectile===true)return Cf6FixedProjectileHarness.emit(props);
        var shell:MovieClip=_root.gameworld.createEmptyMovieClip("recordedEmission"+ticks+"_"+emissions.length,_root.gameworld.getNextHighestDepth());
        if(props.cf6DamageGroup!=null)Cf6DamageGroups.born(shell,props);
        shell.removeMovieClip();return shell;
    }
    private static function find(identity:String):Object {
        for(var i:Number=0;i<metadata.length;i++)if(metadata[i].identity==identity)return metadata[i];
        return null;
    }
    private static function beginScenarios():Void {
        scenarios=[];
        for(var i:Number=0;i<metadata.length;i++){
            var row:Object=metadata[i],p:Object=config.profiles[parameters[row.identity].cf6ProfileId];
            if(scenarios.length==0 && p.roleClass=="ordinary" && p.role=="line")scenarios.push({row:row,label:"ordinary_line",primary:p.budget.primaryTriggerLimit,dual:0,sub:0});
        }
        scenarios.push({row:find("CF6-M-I"),label:"positive_weapon_handoff",primary:2,dual:1,sub:0});
        scenarios.push({row:find("CF6-M-VII"),label:"charge_then_shotgun",primary:1,dual:0,sub:0});
        scenarios.push({row:find("CF6-M-XIII"),label:"primary_then_subweapon",primary:3,dual:0,sub:1});
        scenarios.push({row:find("CF6-M-XVIII"),label:"real_launcher_load",primary:1,dual:0,sub:0});
        scenarios.push({row:find("CF6-M-XX"),label:"g1111_rifle_fallback",primary:1,dual:0,sub:0});
        scenarios.push({row:find("CF6-M-V"),label:"g1111_rocket_fallback",primary:1,dual:0,sub:0});
        for(i=0;i<metadata.length;i++){
            row=metadata[i];p=config.profiles[parameters[row.identity].cf6ProfileId];
            if(p.roleClass=="elite" && p.role=="dual" && row.phase==2){
                scenarios.push({row:row,label:"native_dual",primary:0,dual:p.budget.sidearmSynchronizedTriggerLimit,sub:0});break;
            }
        }
        scenarios.push({row:find("CF6-M-XII"),label:"reverse_rear_guard",primary:1,dual:0,sub:0});
        scenarios.push({row:find("CF6-M-IV"),label:"fixed_bastion",primary:8,dual:0,sub:0});
        scenarios.push({row:find("CF6-M-XV"),label:"pursuit_leash",primary:0,dual:1,sub:0});
        scenarios.push({row:find("CF6-M-XVI"),label:"segmented_lane",primary:3,dual:0,sub:0});
        scenarios.push({row:find("CF6-M-XVII"),label:"landing_watch",primary:2,dual:0,sub:0});
        scenarios.push({row:find("CF6-M-XIX"),label:"bright_burst",primary:2,dual:0,sub:0});
        scenarios.push({row:find("CF6-M-X"),label:"range_rotation",primary:3,dual:1,sub:0});
        scenarios.push({row:find("CF6-M-VIII"),label:"shield_counter",primary:0,dual:0,sub:1});
        scenarios.push({row:find("CF6-M-0"),label:"feint_retreat",primary:0,dual:0,sub:1});
        scenarios.push({row:find("CF6-M-XIV"),label:"alternating_fire",primary:3,dual:0,sub:1});
        scenarios.push({row:find("CF6-M-XI"),label:"punish_commit",primary:2,dual:0,sub:0});
        scenarios.push({row:find("CF6-M-VI"),label:"paired_windows",primary:8,dual:0,sub:0});
        scenarios.push({row:find("CF6-M-III"),label:"reserve_gate",primary:1,dual:0,sub:0});
        scenarios.push({row:find("CF6-M-IX"),label:"robot_observer",primary:1,dual:0,sub:0});
        scenarios.push({row:find("CF6-M-II"),label:"threshold_flush",primary:2,dual:0,sub:0});
        scenarios.push({row:find("CF6-M-XXI"),label:"final_phase_guard",primary:3,dual:0,sub:1});
        scenarios.push({row:find("CF6-M-XVIII"),label:"real_smoke_reload",primary:1,dual:0,sub:0,repeats:2});
        scenarios.push({row:find("CF6-C-WA-P-04"),label:"far_shotgun",primary:1,dual:0,sub:0});
        scenarios.push({row:find("CF6-C-WA-P-01"),label:"rear_crossfire",primary:3,dual:0,sub:0});
        scenarios.push({row:find("CF6-C-WA-P-04"),label:"same_side_flank",movementCase:true});
        scenarios.push({row:find("CF6-C-CU-K-02"),label:"lab_obstacle_lane",movementCase:true});
        var thrown:Object=find("CF6-C-WA-K-05"),throwProfile:Object=config.profiles[parameters[thrown.identity].cf6ProfileId];
        scenarios.push({row:thrown,label:"finite_grenade",primary:throwProfile.budget.primaryTriggerLimit,dual:0,sub:0,repeats:3});
        var precision:Object;
        for(i=0;i<metadata.length;i++)if(config.profiles[parameters[metadata[i].identity].cf6ProfileId].role=="precision"
            && config.profiles[parameters[metadata[i].identity].cf6ProfileId].roleClass=="ordinary"){precision=metadata[i];break;}
        scenarios.push({row:precision,label:"wall_cancel",primary:0,dual:0,sub:0,negative:"wall"});
        scenarios.push({row:precision,label:"offscreen_cancel",primary:0,dual:0,sub:0,negative:"offscreen"});
        scenarios.push({row:precision,label:"target_replacement_cancel",primary:0,dual:0,sub:0,negative:"replacement"});
        if(_root.cf6RealProjectile===true){
            scenarios.push({row:find("CF6-M-V"),label:"g1111_rocket_target_loss",primary:1,dual:0,sub:0,flightMode:"loss"});
            scenarios.push({row:find("CF6-M-V"),label:"g1111_rocket_target_replacement",primary:1,dual:0,sub:0,flightMode:"replacement"});
        }
        if(_root.cf6ProjectileLifetimeOnly===true){
            var selected:Array=[];
            for(var pick:Number=0;pick<scenarios.length;pick++)if(scenarios[pick].flightMode!=undefined)selected.push(scenarios[pick]);
            scenarios=selected;
        }
        cursor=0;phase=2;age=0;current=null;
    }
    private static function startScenario():Void {
        currentScenario=scenarios[cursor];resetWorld(currentScenario.row.mapId);emissions=[];partner=null;externalActor=null;
        _root.控制目标="__no_player";
        var target:MovieClip=world.createEmptyMovieClip("fixedTarget",world.getNextHighestDepth());
        target._x=430;target._y=target.Z轴坐标=300;target.hp=100000;target.version=1;
        target.area=rectangle(target,"area",-20,-120,40,120);target.是否为敌人=false;
        target.dispatcher=new EventDispatcher();
        current=spawn(currentScenario.row);current.攻击目标="fixedTarget";age=0;
        if(currentScenario.label=="rear_crossfire")partner=spawn(find("CF6-C-WA-P-02"));
        if(currentScenario.label=="same_side_flank")partner=spawn(find("CF6-C-WA-P-01"));
        if(currentScenario.label=="paired_windows")partner=spawn(find("CF6-N-PE-01"));
        if(currentScenario.label=="reserve_gate")partner=spawn(find("CF6-N-PE-05"));
    }
    private static function external(kind:String):MovieClip {
        var name:String=kind=="wings"?"fixtureWings":kind=="robot"?"cf6Boss_A20__elderbot":"cf6Boss_A20";
        var actor:MovieClip=world.createEmptyMovieClip(name,world.getNextHighestDepth());
        actor._x=400;actor._y=actor.Z轴坐标=300;actor.version=1;actor.hp=10000;actor.cf6BossIdentity={};
        if(kind=="wings"){
            actor.兵种="敌人-CF6Wings";actor.cf6SpawnWave=1;actor.cf6SpawnEntry=0;actor.cf6SpawnOrdinal=0;
        }else Cf6SoldierSignals.bindBoss(actor,kind);
        return actor;
    }
    private static function scenarioInputs():Void {
        var label:String=currentScenario.label,target:MovieClip=world.fixedTarget;
        if(age==15){
            if(label=="ordinary_line"){
                current.状态改变("长枪攻击");current.状态改变("投掷手雷");
                check(current.soldierAttackOwner==null,"unscheduled base AI cannot strand a fixed shooter");
                target.Z轴坐标=target._y=current.Z轴坐标+18;
            }
            if(label=="lab_obstacle_lane"){
                var env:Object=Cf6FixedChapterFixture.environment("A11");
                _root.collisionLayer.removeMovieClip();
                _root.collisionLayer=_root.createEmptyMovieClip("labTestCollision",_root.getNextHighestDepth());
                _root.Xmin=env.Xmin;_root.Xmax=env.Xmax;_root.Ymin=env.Ymin;_root.Ymax=env.Ymax;
                org.flashNight.arki.collision.CollisionLayerRenderer.drawBoundary(_root.collisionLayer,env.Xmin,env.Xmax,env.Ymin,env.Ymax,300,false);
                org.flashNight.arki.collision.CollisionLayerRenderer.drawPolygons(_root.collisionLayer,env.Collision);
                world._x=-665;world._y=-13;current._x=976;current.Z轴坐标=current._y=479;
                target._x=1230;target.Z轴坐标=target._y=425;
                check(!Mover.isPointValid(976,473) && Mover.isPointValid(976,479) && Mover.isPointValid(1230,425),
                    "real A11 blocker and both observed free endpoints reproduced");
            }
            if(label=="far_shotgun"){current._x=100;target._x=920;}
            if(label=="rear_crossfire"){current._x=1120;partner._x=110;target._x=350;target.方向="左";}
            if(label=="same_side_flank"){_root.控制目标="fixedTarget";current._x=250;partner._x=95;target._x=480;}
            if(currentScenario.flightMode!=undefined)target._x=650;
            if(label=="range_rotation")target._x=550;
            if(label=="shield_counter")Cf6SoldierSignals.event(current,"shield");
            if(label=="threshold_flush")target._x=650;
            if(label=="paired_windows"){target._x=530;partner._x=300;}
            if(partner!=null){
                partner.攻击目标="fixedTarget";
                if(label=="reserve_gate"){
                    partner.手枪.value.shot=partner.手枪弹匣容量;partner.手枪2.value.shot=partner.手枪2弹匣容量;
                }
            }
            if(label=="final_phase_guard")externalActor=external("human");
        }
        if(label=="ordinary_line" && age>=16 && age<=40){
            var state:Object=current.cf6ActionState;
            if(state.active && current.man.cf6Stride._currentframe>1)currentScenario.sawStride=true;
            if(current.soldierShotCount>0 && currentScenario.firstNativeShotAge===undefined)currentScenario.firstNativeShotAge=age;
        }
        if(age>=16 && label=="pursuit_leash")target._x=430+Math.min(50,age-15);
        if(label=="same_side_flank" && current.cf6Observation.flank!=null)currentScenario.routed=true;
        if(label=="offscreen_cancel" && currentScenario.injected)world._x=-current._x-160;
        if(age>=16 && label=="feint_retreat")target._x=430-Math.min(18,age-15)*6-Math.max(0,age-33)*.2;
        if(age==18){
            if(label=="reverse_rear_guard")Cf6SoldierSignals.event(current,"damage");
            if(label=="threshold_flush")target._x=540;
            if(label=="punish_commit"){
                _root.控制目标="fixedTarget";Cf6SoldierSignals.playerState(target,"兵器冲击");
            }
            if(label=="landing_watch" || label=="robot_observer"){
                var kind:String=label=="landing_watch"?"wings":"robot";
                externalActor=external(kind);var action:Object={};
                Cf6SoldierSignals.externalStart(externalActor,kind,action,true);
                Cf6SoldierSignals.externalEnd(externalActor,kind,action,true);
            }
        }
        if(currentScenario.negative!=undefined && !currentScenario.injected && current.cf6ActionState.active
            && current.cf6ActionState.firstShot<0){
            currentScenario.injected=true;
            check(current.cf6ActionState.active,"negative input occurs before the first native discharge "+label);
            if(currentScenario.negative=="offscreen")world._x=-250;
            if(currentScenario.negative=="wall"){
                _root.collisionLayer.clear();_root.collisionLayer.beginFill(0);
                _root.collisionLayer.moveTo(300,200);_root.collisionLayer.lineTo(320,200);
                _root.collisionLayer.lineTo(320,400);_root.collisionLayer.lineTo(300,400);_root.collisionLayer.lineTo(300,200);_root.collisionLayer.endFill();
            }
            if(currentScenario.negative=="replacement"){
                target.removeMovieClip();target=world.createEmptyMovieClip("fixedTarget",world.getNextHighestDepth());
                target._x=430;target._y=target.Z轴坐标=300;target.version=2;target.hp=10000;
                target.area=rectangle(target,"area",-20,-120,40,120);target.dispatcher=new EventDispatcher();
            }
        }
    }
    private static function finishScenario():Void {
        if(currentScenario.label=="ordinary_line"){
            trace("[CF6_FIXED_FIRST_SHOT] targetAge=15 shotAge="+currentScenario.firstNativeShotAge+" movingGait="+currentScenario.sawStride);
            check(currentScenario.firstNativeShotAge>=15 && currentScenario.firstNativeShotAge<=25,"native primary first shot within ten frames of target acquisition, age="+currentScenario.firstNativeShotAge);
            check(currentScenario.sawStride===true,"native firing body advances its lower-body gait while closing Z");
            check(current.cf6Warning==null,"no aiming-line clip allocated");
        }
        var count:Array=[0,0,0,0];
        for(var i:Number=0;i<emissions.length;i++){
            var e:Object=emissions[i];if(e.cycle!=1 || e.identity!==current.cf6UnitIdentity)continue;
            if(e.bit==1)count[0]++;if(e.bit==2)count[1]++;if(e.bit==4)count[2]++;if(e.bit==8)count[3]++;
            check(e.phase==currentScenario.row.phase,"no synthetic phase change "+currentScenario.label);
            if(currentScenario.label=="g1111_rifle_fallback")check(e.split==1 && e.type=="铁枪磁轨弹","fixed rifle one native payload");
            if(currentScenario.label=="g1111_rocket_fallback")check(e.split==6 && e.type=="横向拖尾追踪联弹-普通无壳子弹","fixed rocket six linked units in native payload");
        }
        if(currentScenario.label=="far_shotgun"){
            check(current.cf6FirstPrimaryDistance>650 && current.cf6FirstPrimaryDistance<900 && current._x>100,
                "shotgun commits outside the preferred 180px band and keeps advancing");
            trace("[CF6_FAR_SHOTGUN] distance="+current.cf6FirstPrimaryDistance+" startX=100 endX="+current._x);
        }
        if(currentScenario.label=="rear_crossfire"){
            var delay:Number=current.cf6FirstPrimaryFrame-current.cf6ActionRecord.firstVisibleFrame;
            check(delay>=0 && delay<=12 && current.cf6FirstPrimaryDistance>460
                && current.cf6FirstPrimaryX>current.cf6FirstTargetX && partner.cf6FirstPrimaryX<partner.cf6FirstTargetX,
                "opposite real gunners fire on both sides; rear fires within twelve visible frames");
            trace("[CF6_REAR_FIRST] visibleToShot="+delay+" distance="+current.cf6FirstPrimaryDistance
                +" rearX="+current.cf6FirstPrimaryX+" targetX="+current.cf6FirstTargetX+" oppositeX="+partner.cf6FirstPrimaryX);
        }
        if(currentScenario.label=="lab_obstacle_lane"){
            check(current.cf6NavPlans>0 && current.soldierShotCount>0 && current.cf6FirstPrimaryFrame>=15
                && current.cf6FirstPrimaryFrame<195 && Math.abs(current.Z轴坐标-world.fixedTarget.Z轴坐标)<=24,
                "G3SG1 leaves real A11 obstacle, changes lane and dispatches before 180 active frames");
            trace("[CF6_LAB_ROUTE] plans="+current.cf6NavPlans+" first="+current.cf6FirstPrimaryFrame
                +" distance="+current.cf6FirstPrimaryDistance+" x="+current._x+" z="+current.Z轴坐标+" shots="+current.soldierShotCount);
            _root.collisionLayer.removeMovieClip();
        }else if(currentScenario.movementCase){
            check(currentScenario.routed===true && current._x>world.fixedTarget._x+64
                && partner._x<world.fixedTarget._x-80 && current.soldierShotCount>0 && partner.soldierShotCount>0,
                "one same-side mobile gunner crosses under covering fire and both real weapons discharge");
            trace("[CF6_FLANK] routed="+currentScenario.routed+" left="+partner._x+" right="+current._x
                +" player="+world.fixedTarget._x+" shots="+partner.soldierShotCount+"/"+current.soldierShotCount);
        }else{
        check(count[0]==currentScenario.primary && count[1]==currentScenario.dual && count[2]==currentScenario.dual
            && count[3]==currentScenario.sub,"native commit signature "+currentScenario.label+" = "+count.join("/"));
        check(currentScenario.negative!=undefined?current.cf6ActionState.cancelReason=="target_or_permission":current.cf6ActionState.cancelReason=="complete","native terminal "+currentScenario.label+" reason="+current.cf6ActionState.cancelReason);
        }
        if(currentScenario.flightMode!=undefined){
            // The committed shot has already entered recovery. Target loss
            // retires its carrier and cannot refund or restart that recovery.
            check(current.cf6ActionState.cycle===1 && current.cf6ActionState.primary===1 && emissions.length===1,
                "in-flight target loss preserves exactly one commit and one completed recovery "+currentScenario.label);
        }
        if(currentScenario.label=="real_smoke_reload"){
            var secondShots:Number=0;
            for(i=0;i<emissions.length;i++)if(emissions[i].identity==current.cf6UnitIdentity && emissions[i].cycle==2 && emissions[i].bit==1)secondShots++;
            check(secondShots==1 && current.cf6ActionRecord.reloadSequence>=2,"new FSC7 shot requires actual reload receipt");
            check(current.soldierTacticalStats.smokeReloads>=1 && 200-current._x>0 && 200-current._x<=120.01,"real smoke reload performs bounded collision movement");
        }
        if(currentScenario.label=="finite_grenade"){
            var throws:Number=0;for(i=0;i<emissions.length;i++)if(emissions[i].identity==current.cf6UnitIdentity && emissions[i].bit==16)throws++;
            check(throws==1 && current.cf6ActionState.throwUsed==1 && current.cf6ActionState.cycle>=3,"finite thrown token does not reset across three native cycles");
        }
        if(currentScenario.label=="paired_windows"){
            var partnerFirst:Number=100000,ownFirst:Number=100000;
            for(i=0;i<emissions.length;i++){
                if(emissions[i].identity==partner.cf6UnitIdentity)partnerFirst=Math.min(partnerFirst,emissions[i].frame);
                if(emissions[i].identity==current.cf6UnitIdentity)ownFirst=Math.min(ownFirst,emissions[i].frame);
            }
            check(partnerFirst<ownFirst && ownFirst<100000,"real partner action precedes instructor token transfer");
        }
        if(_root.cf6RealProjectile===true)check(Cf6FixedProjectileHarness.verify(current,currentScenario.label),"real flight and retirement "+currentScenario.label);
        trace("[CF6_FIXED_NATIVE_CASE] "+currentScenario.label+" commits="+count.join("/")+" frames="+age+" reason="+current.cf6ActionState.cancelReason);
        completed++;current.removeMovieClip();current=null;cursor++;age=0;
    }
    private static function tick():Void {
        if(finished)return;
        ticks++;_root.帧计时器.当前帧数=ticks;Cf6SoldierActions.now();
        if(_root.cf6RealProjectile===true)Cf6FixedProjectileHarness.pump();
        for(var l:Number=lifecycles.length-1;l>=0;l--){
            var task:Object=lifecycles[l];
            if(task.unit._parent!==world || task.unit.version!==task.version){lifecycles.splice(l,1);continue;}
            task.fn.apply(null,task.args);
        }
        if(ticks>14000){check(false,"bounded native suite timeout");finish();return;}
        age++;
        if(phase==1){
            if(batch.length==0){
                if(cursor>=metadata.length){beginScenarios();return;}
                var batchMap:String=metadata[cursor].mapId;resetWorld(batchMap);
                for(var b:Number=0;b<8 && cursor<metadata.length && metadata[cursor].mapId==batchMap;b++,cursor++)batch.push({unit:spawn(metadata[cursor]),row:metadata[cursor]});
                age=0;return;
            }
            if(age<12)return;
            for(b=0;b<batch.length;b++){validateActor(batch[b].unit,batch[b].row);batch[b].unit.removeMovieClip();}
            batch=[];return;
        }
        if(phase==2){
            if(cursor>=scenarios.length){finish();return;}
            if(current==null){startScenario();return;}
            if(age==15){
                validateActor(current,currentScenario.row);
                // attachMovie returns before the parent's native initialization.
                // Assign the scripted target after that real birth has completed.
                current.攻击目标="fixedTarget";
                check(world[current.攻击目标].hp>0,"post-birth target input "+currentScenario.label);
            }
            scenarioInputs();
            if(age==20 || age==75 || age==90){
                var bounds:Object=current.man.getBounds(_root), areaBounds:Object=current.area.getBounds(_root);
                trace("[CF6_FIXED_NATIVE_BOUNDS] "+currentScenario.label+" age="+age+" stage="+Stage.width+"x"+Stage.height
                    +" worldXY="+world._x+","+world._y+" actorXYZ="+current._x+","+current._y+","+current.Z轴坐标
                    +" man="+bounds.xMin+","+bounds.xMax+","+bounds.yMin+","+bounds.yMax
                    +" area="+areaBounds.xMin+","+areaBounds.xMax+","+areaBounds.yMin+","+areaBounds.yMax
                    +" visible="+current._visible+" alpha="+current._alpha+" scale="+current._xscale+","+current._yscale
                    +" subConfig="+current.长枪副武器配置.kind+" subLoaded="+current.长枪副武器状态.loaded
                    +" subCap="+current.长枪副武器配置.capacity+" subInitial="+current.长枪副武器配置.initialLoaded
                    +" subAllowed="+current.soldierSubweaponAllowed()+" subFired="+current.长枪.value.subweaponShot);
            }
            if(age==45 || age==75)trace("[CF6_FIXED_NATIVE_POSE] "+currentScenario.label+" root="+current._currentframe
                +" body="+current.man._currentframe+" expected="+current.cf6ExpectedPose+" owner="+current.soldierAttackOwner.mode
                +" poseAge="+current.soldierAttackOwner.poseAge+" can="+current.cf6FixedCanAct(current.man)
                +" gun="+current.长枪_引用+" pistol="+current.手枪_引用+" off="+current.手枪2_引用
                +" muzzle="+current.soldierMuzzleMarker(current.man));
            if(age%120==0)trace("[CF6_FIXED_NATIVE_PROGRESS] "+currentScenario.label+" phase="+current.soldierPhase
                +" state="+current.状态+" cycle="+current.cf6ActionState.cycle+" stage="+current.cf6ActionState.index
                +" mode="+current.soldierAttackOwner.mode+" ready="+current.cf6Observation.modeReady
                +" valid="+current.cf6Observation.targetValid+" visible="+current.cf6Observation.visible
                +" lane="+current.cf6Observation.sameLane+" distance="+current.cf6Observation.distance+" error="+current.cf6FixedError);
            var required:Number=currentScenario.repeats>0?currentScenario.repeats:1;
            if(currentScenario.movementCase){
                if(age>=200 && (_root.cf6RealProjectile!==true || Cf6FixedProjectileHarness.terminal(current)) || age>=400)finishScenario();
                return;
            }
            if(current.cf6ActionState.terminal>=required && (_root.cf6RealProjectile!==true || Cf6FixedProjectileHarness.terminal(current)) || age>=700)finishScenario();
        }
    }
    private static function ordinaryG1111Modes():Void {
        if(world==null)return;
        for(var mode:Number=0;mode<2;mode++){
            var unit:MovieClip=world.createEmptyMovieClip("nonFixedG1111"+mode,world.getNextHighestDepth());
            unit.攻击模式="长枪";unit.长枪={value:{isRocketMode:mode==1}};unit.铁枪之锋倍率=2.3;
            unit.dispatcher=new EventDispatcher();unit.man=unit.createEmptyMovieClip("man",1);
            unit.man.子弹属性={霰弹值:1,子弹速度:50,shootX:0,shootY:0,shootZ:300};
            var ref:Object={自机:unit,装备类型:"长枪",是否为主角:false};
            _root.装备生命周期函数.G1111初始化(ref,{});
            check(ref.cf6FixedNpc===false && ref.isRocketMode===(mode==1),"non-fixed G1111 preserves saved ordinary mode "+mode);
            unit.铁枪之锋许可=false;unit.dispatcher.publish("长枪射击",unit);
            check(unit.man.子弹属性.霰弹值==(mode==1?6:4),"ordinary uncharged G1111 payload remains unchanged "+mode);
            unit.铁枪之锋许可=true;unit.dispatcher.publish("长枪射击",unit);
            check(mode==1?unit.man.子弹属性.霰弹值==37:unit.man.子弹属性.子弹种类=="铁枪聚束射线",
                "ordinary charged G1111 path remains available "+mode);
            unit.dispatcher.destroy();unit.removeMovieClip();
        }
    }
    private static function finish():Void {
        if(finished)return;finished=true;
        ordinaryG1111Modes();
        _root.敌人属性表=savedEnemyProperties;
        if(_root.cf6RealProjectile===true)Cf6FixedProjectileHarness.finish();
        if(driver!=null)driver.removeMovieClip();
        if(world!=null)world.removeMovieClip();
        check(_root.cf6InventoryReads==0 && _root.cf6InventoryWrites==0,"native NPC fixture never accesses player inventory");
        trace("Cf6FixedSoldierNativeTest: "+passed+" passed, "+failed+" failed; "+(_root.cf6ProjectileLifetimeOnly===true?0:158)+" fixed materializations, "+completed+" native action cases");
        if(failed>0)trace("[TEST_FAIL] Cf6FixedSoldierNativeTest suite failed");
        trace("FocusedTestRunId "+(_root.cf6NativeDomain || "cf6-fixed-native")+" Complete: "+_root.cf6FixedNativeRunId);
    }
}
