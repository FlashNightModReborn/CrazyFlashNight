import org.flashNight.arki.scene.Cf6FixedActionsFixture;
import org.flashNight.arki.scene.Cf6SoldierActions;
import org.flashNight.arki.scene.Cf6SoldierSignals;
import org.flashNight.arki.scene.Cf6SoldierPairs;
import org.flashNight.arki.scene.Cf6DamageGroups;
import org.flashNight.arki.scene.StageReturnFlow;

/** Same production functions in AVM1, plus native object-removal ownership. */
class org.flashNight.arki.scene.Cf6FixedActionsTest {
    private static var passed:Number,failed:Number;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[FAIL] Cf6FixedActionsTest "+label);}
    }
    private static function observation():Object {
        return {world:"world1",birth:"birth1",actorVersion:7,frame:0,paused:false,
            alive:true,retired:false,controlled:false,interrupted:false,phase:1,
            targetValid:true,targetKey:"player1",targetVersion:3,visible:true,lineClear:true,sameLane:true,
            distance:230,height:0,inFront:true,retreatAvailable:true,atAnchor:true,
            movingAway:true,approaching:true,subReady:true,primaryLoaded:true,throwReady:true,
            attackEvent:1,attackAge:0,shieldEvent:1,wingsEvent:1,wingsRecovery:true,
            reloadEvent:1,commitEvent:1,commitAge:0,reserveEvent:1,robotEvent:1,
            robotRecovery:true,crossEvent:1,pairEligible:true,fixedModeValid:true,pairTurn:true,
            humanGuardValid:true,guardThreat:true,guardTether:true,behindBirth:false,
            permit:true,subPermit:true,modeReady:true,readyMode:"primary",chargeTerminal:0,
            moveBlocked:false,projectilesTerminal:true,targetX:300,targetY:200,targetZ:300,faceSign:1};
    }
    private static function cost(p:Object,bit:Number):Number {
        if(bit==1)return p.budget.primaryFinalDamageUnitsPerAction===undefined?p.budget.primarySplit:p.budget.primaryFinalDamageUnitsPerAction/p.budget.primaryTriggerLimit;
        if(bit==8)return p.budget.subweaponFinalDamageUnitsPerAction;
        if(bit==16)return 2;
        return p.budget.sidearmProjectilesPerAction/(2*p.budget.sidearmSynchronizedTriggerLimit);
    }
    private static function cycles():Void {
        var rules:Object=Cf6FixedActionsFixture.rules(),config:Object=Cf6FixedActionsFixture.config();
        var ids:Array=Cf6FixedActionsFixture.instructors();
        check(ids.length==22,"all instructor programs present");
        for(var index:Number=0;index<ids.length;index++){
            var p:Object=config.profiles[ids[index]],t:String=p.program.trigger;
            var o:Object=observation(),s:Object=rules.cf6RuleCreate(o.world,o.birth,o.actorVersion),c:Object={};
            if(t=="reverse_rear_guard" || t=="range_rotation" || t=="feint_retreat" || t=="punish_commit")o.phase=2;
            var events:Number=0,warningTicks:Number=0;
            while(s.terminal==0 && o.frame<1600){
                if(s.active){
                    var stage:Object=p.program[s.variant][s.index];o.readyMode=stage.mode;
                    if(stage.kind=="charge" && o.frame-s.entered>=15)o.chargeTerminal=1;
                    if(stage.kind=="move")s.stageMoved+=stage.distance/stage.frames;
                }
                rules.cf6RuleStep(s,p,o,c);
                if(c.warning)warningTicks++;
                for(var bit:Number=1;bit<=16;bit*=2){
                    if((c.fireMask&bit)==0)continue;
                    var units:Number=cost(p,bit);
                    check(rules.cf6RuleCanCommit(s,p,o,bit,units),t+" allowed actual slot "+bit);
                    rules.cf6RuleCommitted(s,p,o,bit,units);events++;
                    check(!rules.cf6RuleCanCommit(s,p,o,bit,units),t+" duplicate denied "+bit);
                }
                if(c.kind!="fire")check(!rules.cf6RuleCanCommit(s,p,o,1,1),t+" closed stage "+c.kind);
                o.frame++;
            }
            check(s.cancelReason=="complete" && s.cycle==1,t+" complete single cycle");
            check(events>0 && warningTicks>=p.extensions.windupFrames,t+" native aim and real event opportunities");
            check(s.primary<=p.budget.primaryTriggerLimit && s.left<=p.budget.sidearmSynchronizedTriggerLimit
                && s.right<=p.budget.sidearmSynchronizedTriggerLimit && s.damageUnits<=p.budget.scriptedCycleDamageUnits,t+" ledger caps");
        }
    }
    private static function edgeCases():Void {
        var rules:Object=Cf6FixedActionsFixture.rules(),config:Object=Cf6FixedActionsFixture.config();
        var p:Object;
        for(var key:String in config.profiles)if(config.profiles[key].program.trigger=="judgment_line")p=config.profiles[key];
        var o:Object=observation(),s:Object=rules.cf6RuleCreate(o.world,o.birth,o.actorVersion),c:Object={};
        var i:Number=0;while(!s.locked && i++<8){o.targetX+=2;rules.cf6RuleStep(s,p,o,c);o.frame++;}
        var locked:Number=s.aimX;o.targetX=900;
        rules.cf6RuleStep(s,p,o,c);o.frame++;
        check(s.aimX==locked,"ready muzzle retains its committed direction");
        o.targetVersion++;rules.cf6RuleStep(s,p,o,c);
        check(!s.active && s.primary==0 && s.readyAt==o.frame+2,"target replacement cancels without refund/retry");
        var terminal:Number=s.terminal;o.paused=true;o.frame+=300;rules.cf6RuleStep(s,p,o,c);
        check(s.terminal==terminal,"pause does not advance transitions");
        for(key in config.profiles)if(config.profiles[key].program.trigger=="reserve_gate")p=config.profiles[key];
        o=observation();o.reserveEvent=0;s=rules.cf6RuleCreate(o.world,o.birth,o.actorVersion);
        for(i=0;i<300;i++){rules.cf6RuleStep(s,p,o,c);o.frame++;}
        check(s.cycle==0,"reserve cannot invent vanguard event");
        o.reserveEvent=1;rules.cf6RuleStep(s,p,o,c);o.frame++;
        o.interrupted=true;rules.cf6RuleStep(s,p,o,c);o.frame++;o.interrupted=false;
        for(i=0;i<180;i++){rules.cf6RuleStep(s,p,o,c);o.frame++;}
        check(s.cycle==1 && s.reserveConsumed==1,"cancelled trigger cannot replay");
        o.reserveEvent=2;rules.cf6RuleStep(s,p,o,c);check(s.cycle==2,"new real event grants next cycle");
    }
    private static function actor(world:MovieClip,id:String,config:Object,profileId:String):Object {
        var u:MovieClip=world.createEmptyMovieClip(id,world.getNextHighestDepth());
        var position:Number=0;
        for(var identity:String in config.identities)if(config.identities[identity].mapId=="A09"){
            if(position++==(id=="fixture1"?0:1)){
                u.cf6UnitIdentity=identity;u.cf6ProfileId=config.identities[identity].profileId;
                u.cf6SourceSeat=config.identities[identity].sourceSeat;break;
            }
        }
        u.version=1;u.hp=100;u.cf6RosterVersion=config.version;
        u.cf6BirthIdentity={};u.cf6BirthX=100;u.cf6BirthZ=300;u.soldierPhase=1;
        u.长枪={value:{shot:0}};u.长枪弹匣容量=10;u.方向="右";
        var record:Object=Cf6SoldierActions.register(u);
        u.cf6ActionState={cycle:1,active:true,terminal:0};return record;
    }
    private static function runtimeAdmission():Void {
        var config:Object=Cf6FixedActionsFixture.config(),id:String=Cf6FixedActionsFixture.instructors()[0];
        check(Cf6SoldierActions.validDefinition(config),"complete closed runtime configuration");
        var stage:Object=config.profiles[id].program.stages[0],previous:String=stage.kind;
        stage.kind="unknown";check(!Cf6SoldierActions.validDefinition(config),"unknown stage rejected before native actor admission");stage.kind=previous;
        var frames:Number=stage.frames;stage.frames=NaN;check(!Cf6SoldierActions.validDefinition(config),"native NaN frame rejected");stage.frames=frames;
        var trigger:String=config.profiles[id].program.trigger;config.profiles[id].program.trigger="adaptive_guess";
        check(!Cf6SoldierActions.validDefinition(config),"unknown instructor tactic cannot silently fall back");config.profiles[id].program.trigger=trigger;
        var actual:String;for(var key:String in config.identities){actual=key;break;}
        var mapping:Object=config.identities[actual];delete config.identities[actual];
        check(!Cf6SoldierActions.validDefinition(config),"missing personnel mapping rejected");config.identities[actual]=mapping;
        mapping.profileId="unknown";check(!Cf6SoldierActions.validDefinition(config),"unknown identity profile rejected");
    }
    private static function nativeOwnership():Void {
        var oldWorld=_root.gameworld,oldClock=_root.帧计时器,oldPause=_root.暂停;
        var world:MovieClip=_root.createEmptyMovieClip("cf6RulesWorld",_root.getNextHighestDepth());
        _root.gameworld=world;_root.帧计时器={当前帧数:0};_root.暂停=false;
        var config:Object=Cf6FixedActionsFixture.config(),profileId:String=Cf6FixedActionsFixture.instructors()[0];
        check(Cf6SoldierActions.bindWorld(world,StageReturnFlow.worldIdentity(world),config,"A09"),"native map identity bound");
        var first:Object=actor(world,"fixture1",config,profileId),second:Object=actor(world,"fixture2",config,profileId);
        check(first!=null && second!=null,"independent native actor births");
        var invalid:MovieClip=world.createEmptyMovieClip("unknownFixedActor",world.getNextHighestDepth());
        invalid.cf6BirthIdentity={};invalid.cf6RosterVersion=config.version;invalid.cf6UnitIdentity="CF6-UNKNOWN";
        invalid.cf6ProfileId=profileId;invalid.version=1;
        check(Cf6SoldierActions.register(invalid)==null,"unknown native identity refused");invalid.removeMovieClip();
        var wing:MovieClip=world.createEmptyMovieClip("leaseWing",world.getNextHighestDepth());
        wing.兵种="敌人-CF6Wings";wing.version=1;wing.hp=100;
        var wingAction:Object={};Cf6SoldierSignals.externalStart(wing,"wings",wingAction,true);
        check(!Cf6SoldierActions.request(first) && first.requestAt>=0,"heavy gun queues during a live Wings action");
        Cf6SoldierSignals.externalEnd(wing,"wings",wingAction,true);
        check(!Cf6SoldierActions.externalMayStart(wing) && Cf6SoldierActions.hasPermit(first),"same-frame Wings restart yields to queued gun");
        check(Cf6SoldierActions.request(first),"first map permit granted");
        var group:Object=Cf6DamageGroups.begin(first,1),props:Object={cf6DamageGroup:group};
        var parent:MovieClip=world.createEmptyMovieClip("parentBullet",100);
        Cf6DamageGroups.born(parent,props);Cf6DamageGroups.seal(group);
        var childProps:Object={};Cf6DamageGroups.inherit(parent,childProps);
        var child:MovieClip=world.createEmptyMovieClip("childBullet",101);
        Cf6DamageGroups.born(child,childProps);parent.removeMovieClip();
        check(group.live==1 && !group.ended,"child inherits lease after parent native removal");
        first.actor.cf6ActionState.active=false;first.actor.cf6ActionState.terminal=1;Cf6SoldierActions.end(first);
        check(!Cf6SoldierActions.request(second),"actor recovery cannot release live child");
        for(var i:Number=0;i<240;i++){_root.帧计时器.当前帧数++;Cf6SoldierActions.now();}
        check(Cf6DamageGroups.live(first,1) && !Cf6SoldierActions.hasPermit(second),"request timeout does not release another group");
        child.removeMovieClip();_root.帧计时器.当前帧数++;Cf6SoldierActions.now();
        check(group.ended && !Cf6DamageGroups.live(first,1),"actual last native removal ends group");
        Cf6SoldierActions.request(second);
        for(i=0;i<12;i++){_root.帧计时器.当前帧数++;Cf6SoldierActions.now();}
        check(Cf6SoldierActions.hasPermit(second),"twelve quiet frames then new permit");
        var unknown:Object=Cf6DamageGroups.begin(second,1);Cf6DamageGroups.seal(unknown);
        second.actor.cf6ActionState.active=false;second.actor.cf6ActionState.terminal=1;Cf6SoldierActions.end(second);
        for(i=0;i<240;i++){_root.帧计时器.当前帧数++;Cf6SoldierActions.now();}
        check(unknown.unknown && !unknown.ended,"missing birth is unresolved, never timed out as safe");
        var oldGroup:Object=Cf6DamageGroups.begin(first,2);
        var oldBullet:MovieClip=world.createEmptyMovieClip("recycledBullet",150);
        Cf6DamageGroups.born(oldBullet,{cf6DamageGroup:oldGroup});Cf6DamageGroups.seal(oldGroup);
        var lateRemove:Function=oldBullet.removeMovieClip;oldBullet.removeMovieClip();
        var freshGroup:Object=Cf6DamageGroups.begin(first,3);
        var freshBullet:MovieClip=world.createEmptyMovieClip("recycledBullet",150);
        Cf6DamageGroups.born(freshBullet,{cf6DamageGroup:freshGroup});Cf6DamageGroups.seal(freshGroup);
        lateRemove.call(freshBullet);
        check(freshBullet._parent===world && freshGroup.live==1 && !freshGroup.ended,"old removal callback cannot retire native successor");
        freshBullet.removeMovieClip();check(freshGroup.ended,"successor ends only through its own removal");
        var oldControl:String=_root.控制目标;_root.控制目标=first.actor._name;
        var playerBody:MovieClip=first.actor.createEmptyMovieClip("man",250);
        var playerRoom:Object=Cf6SoldierActions.context();
        Cf6SoldierSignals.playerState(first.actor,"兵器跑");
        check(playerRoom.player.sequence===undefined,"ordinary running is not a committed dash");
        Cf6SoldierSignals.playerState(first.actor,"兵器冲击");var commit:Number=playerRoom.player.sequence;
        check(commit>0,"actual dash state has a version-bound commitment");
        Cf6SoldierSignals.playerContainer(first.actor,"weapon","刀剑1连招",playerBody);
        check(playerRoom.player.sequence===commit,"container and state callbacks cannot double-count one body");
        playerBody.removeMovieClip();playerBody=first.actor.createEmptyMovieClip("man",250);
        Cf6SoldierSignals.playerContainer(first.actor,"skill","兴奋剂",playerBody);
        check(playerRoom.player.sequence===commit,"buff container does not pretend to be an attack");
        Cf6SoldierSignals.playerContainer(first.actor,"skill","闪现",playerBody);
        check(playerRoom.player.sequence>commit,"fresh native dash container has a new commitment");
        commit=playerRoom.player.sequence;
        Cf6SoldierSignals.playerContainer(second.actor,"skill","闪现",playerBody);
        check(playerRoom.player.sequence===commit,"foreign actor or body cannot report player action");
        _root.控制目标=oldControl;
        var oldKey:String=Cf6SoldierSignals.identity(first.actor);
        first.actor.removeMovieClip();
        var replacement:MovieClip=world.createEmptyMovieClip("fixture1",world.getNextHighestDepth());replacement.version=1;
        check(Cf6SoldierSignals.identity(replacement)!=oldKey && !Cf6SoldierActions.actorValid(first),"same native path cannot inherit old actor identity");
        world.removeMovieClip();_root.gameworld=oldWorld;_root.帧计时器=oldClock;_root.暂停=oldPause;
        Cf6SoldierActions.tick();
    }
    private static function suppressionCases():Void {
        var rules:Object=Cf6FixedActionsFixture.rules(),config:Object=Cf6FixedActionsFixture.config(),p:Object;
        var count:Number=0;
        for(var key:String in config.profiles)if(config.profiles[key].program.suppression!==undefined){
            count++;if(config.profiles[key].roleClass=="ordinary")p=config.profiles[key];
        }
        var personnel:Number=0;
        for(key in config.identities)if(config.profiles[config.identities[key].profileId].program.suppression!==undefined)personnel++;
        check(count===11 && personnel===19 && p!=null,"nineteen actual machinegunners share eleven closed profiles");
        var contract:Object=org.flashNight.arki.scene.Cf6SoldierProgramContract;
        check(contract.profile(p),"closed machinegun profile admitted");
        var spec:Object=p.program.suppression;
        spec.fireFrames=61;check(!contract.profile(p),"sustained fire cannot exceed sixty active frames");spec.fireFrames=60;
        var originalType:String=spec.weaponType;spec.weaponType="狙击枪";check(!contract.profile(p),"non-machinegun cannot claim sustained contract");spec.weaponType=originalType;
        var budget:Number=p.budget.primaryTriggerLimit;p.budget.primaryTriggerLimit=61;
        check(!contract.profile(p),"sustained physical trigger bound remains closed");p.budget.primaryTriggerLimit=budget;
        var stage:Object;
        for(var i:Number=0;i<p.program.stages.length;i++)if(p.program.stages[i].kind=="fire" && p.program.stages[i].mode=="primary")stage=p.program.stages[i];
        var gap:Number=stage.gap;stage.gap=2;check(!contract.profile(p),"time window cannot drift into a separate event schedule");stage.gap=gap;
        delete p.program.suppression;check(!contract.profile(p),"ordinary contract cannot inherit the machinegun budget");p.program.suppression=spec;
        var o:Object=observation(),s:Object=rules.cf6RuleCreate(o.world,o.birth,o.actorVersion),c:Object={};
        var first:Number=-1,last:Number=-1;
        while(s.terminal==0 && o.frame<600){
            if(s.active)o.readyMode=p.program[s.variant][s.index].mode;
            rules.cf6RuleStep(s,p,o,c);
            if((c.fireMask&1)!=0){
                check(rules.cf6RuleCanCommit(s,p,o,1,cost(p,1)),"machinegun time window grants a legal frame");
                rules.cf6RuleCommitted(s,p,o,1,cost(p,1));
                check(!rules.cf6RuleCanCommit(s,p,o,1,cost(p,1)),"one primary commit maximum in an active frame");
                if(first<0)first=o.frame;last=o.frame;
            }
            o.frame++;
        }
        check(s.primary===60 && last-first===59,"unthrottled model reaches exactly the physical sixty-frame ceiling");
        check(s.cancelReason=="complete" && o.frame-last>=30,"same production interpreter enforces sustained recovery");
        for(var mode:Number=0;mode<3;mode++){
            o=observation();s=rules.cf6RuleCreate(o.world,o.birth,o.actorVersion);
            while(s.primary<5 && o.frame<300){
                if(s.active)o.readyMode=p.program[s.variant][s.index].mode;
                rules.cf6RuleStep(s,p,o,c);
                if((c.fireMask&1)!=0 && rules.cf6RuleCanCommit(s,p,o,1,cost(p,1)))rules.cf6RuleCommitted(s,p,o,1,cost(p,1));
                o.frame++;
            }
            var previous:Number=s.primary;
            o.paused=true;rules.cf6RuleStep(s,p,o,c);
            check(s.primary===previous && c.fireMask===0 && s.active,"pause never advances sustained fire");o.paused=false;
            if(mode==0)o.targetVersion++;else if(mode==1)o.lineClear=false;else o.interrupted=true;
            rules.cf6RuleStep(s,p,o,c);
            check(!s.active && s.primary===previous && c.fireMask===0,"sustained fire still cancels for target, wall or interruption "+mode);
        }
    }
    public static function runAllTests():Void {
        passed=failed=0;runtimeAdmission();cycles();edgeCases();nativeOwnership();suppressionCases();
        trace("Cf6FixedActionsTest: "+passed+" passed, "+failed+" failed; 22 same-source cycles and native ownership");
        if(failed>0)trace("[TEST_FAIL] Cf6FixedActionsTest suite failed");
    }
}
