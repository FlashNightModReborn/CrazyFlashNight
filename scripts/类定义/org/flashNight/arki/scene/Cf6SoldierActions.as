import org.flashNight.arki.collision.CollisionLayerRenderer;
import org.flashNight.arki.scene.Cf6SoldierSignals;
import org.flashNight.arki.scene.Cf6SoldierPairs;
import org.flashNight.arki.scene.Cf6DamageGroups;
import org.flashNight.arki.scene.StageReturnFlow;

/** One map owns fixed actor identities, active-frame clocks and hazard grants. */
class org.flashNight.arki.scene.Cf6SoldierActions {
    private static var room:Object;
    private static var generation:Number=0;
    private static var watcher:MovieClip;
    public static function context():Object {return current()?room:null;}
    public static function current():Boolean {
        return room!=null && room.world===_root.gameworld && room.owner===StageReturnFlow.worldIdentity(_root.gameworld);
    }
    public static function validDefinition(config:Object):Boolean {
        return org.flashNight.arki.scene.Cf6SoldierProgramContract.valid(config);
    }
    public static function bindWorld(world:MovieClip,owner:Object,config:Object,mapId:String):Boolean {
        if(world!==_root.gameworld || owner==null || owner!==StageReturnFlow.worldIdentity(world)
            || !validDefinition(config))return false;
        if(current() && room.owner===owner)return room.config.version===config.version;
        room={world:world,owner:owner,config:config,mapId:mapId,key:"fixed-map-"+(++generation),
            clock:0,rawFrame:-1,sequence:0,actors:{},external:{},player:{},lease:null,
            requests:[],quietUntil:0,nextFlankCheck:0,error:""};
        Cf6SoldierSignals.bindRoom(room);Cf6DamageGroups.bindWorld(world,owner);Cf6SoldierPairs.bindRoom(room);
        if(watcher==null || watcher._name==undefined)watcher=_root.createEmptyMovieClip("__cf6SoldierActions",_root.getNextHighestDepth());
        watcher.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6SoldierActions.tick();};
        return true;
    }
    public static function now():Number {
        if(!current())return -1;
        var raw:Number=_root.帧计时器.当前帧数;
        if(!_root.暂停 && isFinite(raw) && raw!==room.rawFrame){
            room.rawFrame=raw;room.clock++;
            Cf6DamageGroups.observe();Cf6SoldierPairs.tick();pollLease();
        }
        return room.clock;
    }
    public static function tick():Void {
        if(!current()){if(watcher!=null)delete watcher.onEnterFrame;return;}
        now();
    }
    public static function register(actor:MovieClip):Object {
        if(!current() && !org.flashNight.arki.scene.Cf6Type61Service.ensureFixedWorld(_root.gameworld))return null;
        if(!current() || actor._parent!==room.world || actor.cf6RosterVersion!==room.config.version
            || actor.cf6BirthIdentity==null || typeof actor.cf6UnitIdentity!="string")return null;
        var identity:Object=room.config.identities[actor.cf6UnitIdentity];
        if(identity==null || identity.mapId!==room.mapId || identity.profileId!==actor.cf6ProfileId
            || identity.sourceSeat!==actor.cf6SourceSeat)return null;
        var profile:Object=room.config.profiles[actor.cf6ProfileId];
        if(profile==null || profile.program==null)return null;
        var previous:Object=room.actors[actor.cf6UnitIdentity];
        if(previous!=null)return Cf6SoldierSignals.owns(previous) && previous.actor===actor?previous:null;
        var key:String=Cf6SoldierSignals.identity(actor);if(key=="")return null;
        var record:Object={actor:actor,name:actor._name,version:actor.version,key:key,
            worldEpoch:room.owner,signalMark:actor.__cf6SignalIdentity,birthMark:actor.cf6BirthIdentity,
            identity:actor.cf6UnitIdentity,profile:profile,events:{},eventFrames:{},
            birthX:actor.cf6BirthX,birthZ:actor.cf6BirthZ,birthSign:actor.方向=="左"?-1:1,
            reloadSequence:actor.长枪.value.shot<actor.长枪弹匣容量?1:0,requestAt:-1,
            lastX:actor._x,lastTargetX:NaN,lastDistance:NaN,lastObserveFrame:-1,crossSequence:0,
            crossWasOutside:false,boundaryDisabled:false,combatDead:false,terminalSeen:0};
        room.actors[record.identity]=record;actor.cf6ActionRecord=record;
        return record;
    }
    public static function actorValid(record:Object):Boolean {
        return Cf6SoldierSignals.owns(record) && record.actor.cf6BirthIdentity===record.birthMark
            && record.actor.cf6ActionRecord===record;
    }
    public static function visible(actor:MovieClip,inset:Number):Boolean {
        if(!current() || actor._parent!==room.world || actor._visible!==true || actor._alpha<=0 || actor.man==null)return false;
        // A long barrel or a single cropped boot must not disarm a visible unit.
        var box:Object=actor.area!=null?actor.area.getBounds(_root):actor.man.getBounds(_root);
        return isFinite(box.xMin) && isFinite(box.xMax) && isFinite(box.yMin) && isFinite(box.yMax)
            && box.xMax>box.xMin && box.yMax>box.yMin && box.xMax>inset && box.xMin<Stage.width-inset
            && box.yMax>24 && box.yMin<Stage.height-48;
    }
    public static function pointVisible(x:Number,y:Number,inset:Number):Boolean {
        if(!current() || !isFinite(x) || !isFinite(y))return false;
        var p:Object={x:x,y:y};room.world.localToGlobal(p);
        return p.x>=inset && p.x<=Stage.width-inset && p.y>=24 && p.y<=Stage.height-48;
    }
    /** The movement collision surface owns hard map obstruction. Sample only
     * the straight ground lane; L-shaped walkability is not a firing line. */
    public static function clearLane(actor:MovieClip,target:MovieClip):Boolean {
        if(!current() || actor._parent!==room.world || target._parent!==room.world
            || _root.collisionLayer==null)return false;
        var dx:Number=target._x-actor._x,dz:Number=target.Z轴坐标-actor.Z轴坐标;
        var distance:Number=Math.sqrt(dx*dx+dz*dz);
        if(!isFinite(distance) || distance>1240)return false;
        var steps:Number=Math.max(1,Math.ceil(distance/8));
        // The production collision layer lives on _root. Mover.move2D and
        // move25D query it in ground coordinates, independently of the camera.
        var x:Number=actor._x,z:Number=actor.Z轴坐标,stepX:Number=dx/steps,stepZ:Number=dz/steps;
        for(var i:Number=1;i<steps;i++){
            x+=stepX;z+=stepZ;
            if(!org.flashNight.arki.spatial.move.Mover.isPointValid(x,z))return false;
        }
        if(!org.flashNight.arki.spatial.move.Mover.isPointValid(target._x,target.Z轴坐标))return false;
        return true;
    }
    private static function laneFor(record:Object,target:MovieClip,o:Object,exact:Boolean):Boolean {
        var actor:MovieClip=record.actor,layer:MovieClip=_root.collisionLayer;
        var revision:Number=CollisionLayerRenderer.revision;
        if(record.lineTarget===target && record.lineVersion===target.version && record.lineLayer===layer
            && record.lineRevision===revision && o.frame-record.lineFrame<16){
            if(record.lineX===actor._x && record.lineZ===actor.Z轴坐标
                && record.lineTX===target._x && record.lineTZ===target.Z轴坐标
                && (!exact || record.exactFrame===o.frame))return record.lineClear;
            // A moving actor may plan on a recent observation. Both actual
            // weapon boundaries require the current, exact endpoints.
            if(!exact && o.frame-record.lineFrame<4)return record.lineClear;
        }
        record.lineTarget=target;record.lineVersion=target.version;record.lineLayer=layer;record.lineRevision=revision;
        record.lineX=actor._x;record.lineZ=actor.Z轴坐标;record.lineTX=target._x;record.lineTZ=target.Z轴坐标;
        record.lineFrame=o.frame;record.exactFrame=exact?o.frame:-1;
        record.lineClear=clearLane(actor,target);return record.lineClear;
    }
    public static function refreshFire(record:Object,target:MovieClip,o:Object,exact:Boolean):Void {
        o.frame=now();var actor:MovieClip=record.actor,p:Object=record.profile.program;
        o.world=current()?room.key:"";o.birth=record.key;o.actorVersion=actor.version;
        o.alive=actorValid(record) && actor.hp>0;o.retired=actor.cf6EncounterRetired===true;
        o.paused=_root.暂停===true;o.phase=actor.soldierPhase;
        o.controlled=actor._name===_root.控制目标 && _root.控制目标全自动===false;
        o.interrupted=actor.倒地===true || actor.浮空===true || actor.硬直中===true
            || actor.状态=="被击" || actor.状态=="近战"
            || actor.状态=="投掷手雷" && !actor.soldierAttackOwner.fixed;
        o.targetValid=target!=null && target._parent===room.world && target.hp>0 && target.area!=null;
        o.targetKey=o.targetValid?Cf6SoldierSignals.identity(target):"";o.targetVersion=target.version;
        o.targetX=target._x;o.targetY=target._y-60;o.targetZ=target.Z轴坐标;
        var dx:Number=target._x-actor._x,dz:Number=target.Z轴坐标-actor.Z轴坐标;
        o.distance=Math.abs(dx);o.height=Math.max(0,target.Z轴坐标-target._y);
        o.sameLane=Math.abs(dz)<=p.lane;o.faceSign=dx<0?-1:1;o.inFront=dx*(actor.方向=="左"?-1:1)>0;
        o.visible=o.targetValid && visible(actor,4) && pointVisible(target._x,target._y-60,4);
        if(o.visible && record.firstVisibleFrame==undefined)record.firstVisibleFrame=o.frame;
        o.lineClear=false;o.obstructed=false;
        if(o.visible && (o.sameLane || actor.cf6ActionState.active) && o.distance<=p.fireDistance){
            o.lineClear=laneFor(record,target,o,exact);o.obstructed=!o.lineClear;
        }
        o.subReady=actor.soldierSubweaponAllowed() && actor.长枪副武器状态.loaded>0;
        o.throwReady=actor.soldierCanGrenade();
        o.permit=hasPermit(record);o.subPermit=o.permit;
        o.fixedModeValid=typeof actor.cf6G1111FixedMode=="boolean" && actor.长枪.name=="G1111"
            && actor.长枪.value.isRocketMode===actor.cf6G1111FixedMode;
    }
    public static function observe(record:Object,target:MovieClip,o:Object):Void {
        refreshFire(record,target,o,false);
        var actor:MovieClip=record.actor;
        if(o.targetValid && o.alive && !o.retired && !o.controlled && target._name===_root.控制目标)
            updateFlank(target,o.frame);
        o.flank=room.flank.record===record && room.flank.target===target?room.flank:null;
        o.atAnchor=Math.abs(actor._x-record.birthX)<=48 && Math.abs(actor.Z轴坐标-record.birthZ)<=24;
        o.retreatAvailable=actor.soldierIsElite===true && !o.interrupted;
        if(record.pressureTarget!==o.targetKey){record.pressureTarget=o.targetKey;record.pressureSince=o.frame;}
        o.pressureReady=o.targetValid && o.frame-record.pressureSince>=5;
        o.hazardOccupied=room.lease!=null && room.lease.record!==record || Cf6SoldierSignals.externalBusy();
        o.approaching=false;o.movingAway=false;
        if(o.frame!==record.lastObserveFrame){
            if(isFinite(record.lastTargetX) && record.lastTargetKey===o.targetKey){
                var displacement:Number=(target._x-record.lastTargetX)*o.faceSign;
                record.approaching=displacement<-.1;record.movingAway=displacement>.1;
            }else{record.approaching=false;record.movingAway=false;}
            record.lastTargetX=target._x;record.lastTargetKey=o.targetKey;record.lastObserveFrame=o.frame;
        }
        o.approaching=record.approaching;o.movingAway=record.movingAway;
        var birthDistance:Number=(target._x-record.birthX)*record.birthSign;
        if(o.targetValid && birthDistance<0)record.boundaryDisabled=true;
        if(record.lastCrossTarget!==o.targetKey){record.crossWasOutside=false;record.lastCrossTarget=o.targetKey;}
        if(o.targetValid && birthDistance>420)record.crossWasOutside=true;
        if(record.crossWasOutside && birthDistance>=220 && birthDistance<=420){
            record.crossSequence=++room.sequence;record.crossWasOutside=false;
        }
        o.behindBirth=record.boundaryDisabled;o.crossEvent=record.crossSequence;
        o.primaryLoaded=actor.长枪.value.shot<actor.长枪弹匣容量;
        o.projectilesTerminal=!Cf6DamageGroups.live(record,actor.cf6ActionState.cycle);
        Cf6SoldierSignals.fill(record,target,o);Cf6SoldierPairs.fill(record,target,o);
    }
    /** Keep existing crossfire. When all the guns are on one side, one mobile
     * rifleman may use a separate ground lane to reach the empty side. */
    private static function updateFlank(target:MovieClip,frame:Number):Void {
        var plan:Object=room.flank;
        if(plan!=null){
            var moving:MovieClip=plan.record.actor;
            if(plan.target===target && actorValid(plan.record) && moving.hp>0 && moving.soldierPhase==2
                && frame<plan.expires && (moving._x-target._x)*plan.side<plan.distance-16)return;
            room.flank=null;room.nextFlankCheck=frame+90;
        }
        if(frame<room.nextFlankCheck)return;
        room.nextFlankCheck=frame+24;
        if(_root.Xmax-_root.Xmin<800 || _root.Ymax-_root.Ymin<72)return;
        var side:Number=0,count:Number=0,nearest:Number=620,best:Object=null;
        for(var id:String in room.actors){
            var record:Object=room.actors[id],unit:MovieClip=record.actor;
            if(!actorValid(record) || !(unit.hp>0) || unit.soldierPhase==0
                || unit.攻击目标!==target._name || unit.cf6EncounterRetired===true)continue;
            var dx:Number=unit._x-target._x;
            if(Math.abs(dx)<24)continue;
            var currentSide:Number=dx<0?-1:1;
            if(side!=0 && side!=currentSide)return;
            side=currentSide;count++;
            var profile:Object=record.profile,distance:Number=Math.abs(dx);
            if(unit.soldierPhase==2 && profile.roleClass!="instructor"
                && (profile.strategy=="mobile" || profile.role=="mobile" || profile.role=="dual" || profile.role=="breach")
                && !unit.倒地 && !unit.浮空 && distance<nearest){
                best=record;nearest=distance;
            }
        }
        if(count<2 || best==null)return;
        var roomLeft:Number=side>0?target._x-_root.Xmin:_root.Xmax-target._x;
        var stand:Number=Math.min(240,Math.min(best.profile.program.stopDistance,roomLeft-36));
        if(stand<100)return;
        var laneSign:Number=target.Z轴坐标-_root.Ymin>_root.Ymax-target.Z轴坐标?-1:1;
        room.flank={record:best,target:target,side:-side,distance:stand,laneSign:laneSign,expires:frame+180};
    }
    public static function request(record:Object):Boolean {
        if(!actorValid(record) || !(record.actor.hp>0))return false;
        if(hasPermit(record))return true;
        if(record.requestAt<0){record.requestAt=room.clock;room.requests.push(record);}
        pollLease();return hasPermit(record);
    }
    public static function hasPermit(record:Object):Boolean {
        var lease:Object=room.lease;
        return current() && lease!=null && lease.record===record && !lease.finished
            && actorValid(record) && !Cf6SoldierSignals.externalBusy();
    }
    public static function externalMayStart(actor:Object):Boolean {
        if(!current())org.flashNight.arki.scene.Cf6Type61Service.ensureFixedWorld(_root.gameworld);
        if(!current() || actor._parent!==room.world || actor.兵种!="敌人-CF6Wings")return true;
        now();
        // A Wings action may finish and another start in the same frame.
        if(room.lease==null && room.requests.length>0)pollLease();
        var lease:Object=room.lease;
        if(lease==null)return !Cf6SoldierSignals.externalBusy();
        // An emitted group keeps its ownership. A fresh Wings action waits;
        // it cannot acquire the map while the previous projectile still lives.
        return false;
    }
    public static function recovering(record:Object):Void {
        if(current() && room.lease.record===record)room.lease.finished=true;
        // pollLease still requires all of the original damage objects to retire.
    }
    public static function end(record:Object):Void {
        if(!current() || record==null)return;
        record.requestAt=-1;
        if(room.lease.record===record)room.lease.finished=true;
        Cf6SoldierPairs.terminal(record);
        pollLease();
    }
    private static function pollLease():Void {
        // Waiting requests age independently of the current damage group's
        // lease. Expiring a request cannot release that group or bank a burst.
        for(var pendingIndex:Number=room.requests.length-1;pendingIndex>=0;pendingIndex--){
            var pending:Object=room.requests[pendingIndex];
            if(pending.requestAt<0 || !actorValid(pending) || !(pending.actor.hp>0)
                || room.clock-pending.requestAt>=180){
                var expired:Boolean=pending.requestAt>=0 && room.clock-pending.requestAt>=180;
                pending.requestAt=-1;room.requests.splice(pendingIndex,1);
                if(expired && typeof pending.actor.cf6FixedPermitExpired=="function")pending.actor.cf6FixedPermitExpired();
            }
        }
        var lease:Object=room.lease;
        if(lease!=null){
            var record:Object=lease.record,state:Object=record.actor.cf6ActionState;
            if(!actorValid(record) || !(record.actor.hp>0) || record.actor.soldierPhase==0)lease.finished=true;
            if(!state.active && room.clock>lease.grantedAt+1)lease.finished=true;
            if(lease.finished && !Cf6DamageGroups.live(record,-1)){
                room.lease=null;room.quietUntil=room.clock+12;
            }
            else return;
        }
        if(room.clock<room.quietUntil || Cf6SoldierSignals.externalBusy() || Cf6DamageGroups.unresolved())return;
        for(var i:Number=0;i<room.requests.length;i++){
            var candidate:Object=room.requests[i];
            if(candidate.requestAt<0 || !actorValid(candidate) || !(candidate.actor.hp>0)
                || room.clock-candidate.requestAt>=180){
                candidate.requestAt=-1;room.requests.splice(i--,1);continue;
            }
            if(!Cf6SoldierPairs.mayRequest(candidate))continue;
            room.lease={record:candidate,cycle:candidate.actor.cf6ActionState.cycle+1,
                grantedAt:room.clock,finished:false};candidate.requestAt=-1;room.requests.splice(i,1);return;
        }
    }
    public static function error(record:Object,reason:String):Void {
        if(record!=null){record.error=reason;record.actor.cf6FixedError=reason;end(record);}
        if(current())room.error=reason;
        trace("[CF6_FIXED_ACTION_ERROR] "+reason);
    }
}
