import org.flashNight.arki.scene.Cf6SoldierActions;
import org.flashNight.arki.scene.Cf6SoldierSignals;

/** Explicit identities only. Assembly is one bounded collision-resolved attempt. */
class org.flashNight.arki.scene.Cf6SoldierPairs {
    private static var room:Object;
    public static function bindRoom(context:Object):Void {
        room=context;
        room.g1111={mode:"waiting",firstSeen:-1,startedAt:-1,attempts:0,travelX:0,travelZ:0,
            blocked:0,lastMoveFrame:-1,judgeKey:"",popeKey:"",turn:"CF6-M-XX",reason:""};
        room.alternating={turn:"CF6-N-PE-01",after:0,epoch:1,deadTurnStarted:-1};
    }
    private static function living(record:Object):Boolean {
        return Cf6SoldierActions.actorValid(record) && record.actor.hp>0 && !record.actor.cf6EncounterRetired;
    }
    private static function fallback(reason:String):Void {
        room.g1111.mode="fallback";room.g1111.reason=reason;
    }
    public static function tick():Void {
        var pair:Object=room.g1111,judge:Object=room.actors["CF6-M-XX"],pope:Object=room.actors["CF6-M-V"];
        if(room.mapId=="A19" && pair.mode!="fallback"){
            if((judge!=null || pope!=null) && pair.firstSeen<0)pair.firstSeen=room.clock;
            if(pair.mode=="waiting"){
                if(living(judge) && living(pope) && judge.actor.soldierPhase==1 && pope.actor.soldierPhase==1){
                    pair.mode="assembly";pair.startedAt=room.clock;pair.attempts=1;
                    pair.judgeKey=judge.key;pair.popeKey=pope.key;
                }else if(pair.firstSeen>=0 && room.clock-pair.firstSeen>=150)fallback("partner_unavailable");
            }else if(!living(judge) || !living(pope) || judge.key!==pair.judgeKey || pope.key!==pair.popeKey
                || judge.actor.soldierPhase!=1 || pope.actor.soldierPhase!=1)fallback("partner_lifetime");
            else if(pair.mode=="assembly" && room.clock-pair.startedAt>=150)fallback("assembly_timeout");
        }
        var alt:Object=room.alternating,holder:Object=room.actors[alt.turn];
        if(holder!=null && (holder.combatDead || holder.retired)){
            if(alt.deadTurnStarted<0)alt.deadTurnStarted=room.clock;
            if(room.clock-alt.deadTurnStarted>=48){
                alt.turn=alt.turn=="CF6-N-PE-01"?"CF6-M-VI":"CF6-N-PE-01";
                alt.epoch++;alt.after=room.clock;alt.deadTurnStarted=-1;
            }
        }
    }
    private static function geometry(target:MovieClip):Boolean {
        var judge:Object=room.actors["CF6-M-XX"],pope:Object=room.actors["CF6-M-V"];
        if(!living(judge) || !living(pope) || target._parent!==room.world || !(target.hp>0))return false;
        var a:MovieClip=judge.actor,b:MovieClip=pope.actor;
        return a.soldierPhase==1 && b.soldierPhase==1 && a.攻击目标===b.攻击目标
            && Cf6SoldierActions.visible(a,64) && Cf6SoldierActions.visible(b,64)
            && Cf6SoldierActions.pointVisible(target._x,target._y-60,64)
            && Math.abs(target._x-a._x)>=180 && Math.abs(target._x-a._x)<=680
            && Math.abs(target._x-b._x)>=220 && Math.abs(target._x-b._x)<=460
            && Math.abs(target.Z轴坐标-a.Z轴坐标)<=20 && Math.abs(target.Z轴坐标-b.Z轴坐标)<=24;
    }
    public static function assembly(record:Object):Boolean {
        var pair:Object=room.g1111;
        if(record.identity!="CF6-M-XX" && record.identity!="CF6-M-V")return false;
        if(pair.mode=="waiting")return false;
        if(pair.mode!="assembly")return false;
        var actor:MovieClip=record.actor,target:MovieClip=room.world[actor.攻击目标];
        if(geometry(target)){pair.mode="bound";return false;}
        var seen:Object=actor.cf6Observation;
        if(seen.targetValid && seen.visible && seen.sameLane && seen.lineClear
            && seen.distance<=record.profile.program.maxDistance){
            fallback("target_in_personal_firing_lane");return false;
        }
        if(record.identity!="CF6-M-V" || pair.lastMoveFrame===room.clock)return false;
        pair.lastMoveFrame=room.clock;
        if(actor.硬直中 || actor.倒地 || actor.浮空){fallback("assembly_interrupted");return false;}
        var partner:MovieClip=room.actors["CF6-M-XX"].actor;
        var dx:Number=partner._x-actor._x,dz:Number=partner.Z轴坐标-actor.Z轴坐标;
        var amountX:Number=Math.min(Math.max(0,Math.abs(dx)-810),Math.max(0,480-pair.travelX),actor.行走X速度);
        var amountZ:Number=Math.min(Math.max(0,Math.abs(dz)-12),Math.max(0,120-pair.travelZ),actor.行走Y速度);
        var beforeX:Number=actor._x,beforeZ:Number=actor.Z轴坐标;
        if(amountX>0)actor.soldierTacticalMove(dx<0?"左":"右",amountX);
        if(amountZ>0)actor.soldierTacticalMove(dz<0?"上":"下",amountZ);
        var movedX:Number=Math.abs(actor._x-beforeX),movedZ:Number=Math.abs(actor.Z轴坐标-beforeZ);
        pair.travelX+=movedX;pair.travelZ+=movedZ;
        if(movedX+movedZ<.1)pair.blocked++;else pair.blocked=0;
        actor.cf6FixedWalkPose(dx<0?-1:1,movedX+movedZ>.1);
        if(pair.blocked>=15)fallback("assembly_blocked");
        else if(pair.travelX>=480 || pair.travelZ>=120)fallback("assembly_budget");
        else if(amountX<=0 && amountZ<=0 && !geometry(target))fallback("no_shared_viewport_or_lane");
        return pair.mode=="assembly";
    }
    public static function fill(record:Object,target:MovieClip,o:Object):Void {
        var id:String=record.identity,pair:Object=room.g1111;
        o.pairEligible=true;o.pairFallback=false;o.recoveryFloor=0;
        if(id=="CF6-M-XX" || id=="CF6-M-V"){
            if(pair.mode=="bound" && !geometry(target))fallback("pair_geometry_lost");
            o.pairFallback=pair.mode=="fallback";
            o.pairEligible=o.pairFallback || pair.mode=="waiting" || pair.mode=="bound" && pair.turn===id && geometry(target);
            if(o.pairFallback)o.recoveryFloor=id=="CF6-M-XX"?90:120;
        }
        o.alternatingMember=id=="CF6-N-PE-01" || id=="CF6-M-VI";
        o.pairTurn=!o.alternatingMember || room.alternating.turn===id && room.clock>=room.alternating.after;
        o.forcePermit=o.alternatingMember;
    }
    public static function mayRequest(record:Object):Boolean {
        var id:String=record.identity;
        if(id=="CF6-N-PE-01" || id=="CF6-M-VI")
            return room.alternating.turn===id && room.clock>=room.alternating.after;
        if((id=="CF6-M-XX" || id=="CF6-M-V") && room.g1111.mode=="bound")return room.g1111.turn===id;
        return true;
    }
    public static function terminal(record:Object):Void {
        var state:Object=record.actor.cf6ActionState;
        if(state==null || record.terminalSeen>=state.terminal)return;
        record.terminalSeen=state.terminal;
        var id:String=record.identity;
        if(room.g1111.mode=="bound" && room.g1111.turn===id)
            room.g1111.turn=id=="CF6-M-XX"?"CF6-M-V":"CF6-M-XX";
        if((id=="CF6-N-PE-01" || id=="CF6-M-VI") && room.alternating.turn===id){
            room.alternating.turn=id=="CF6-N-PE-01"?"CF6-M-VI":"CF6-N-PE-01";
            room.alternating.epoch++;room.alternating.after=room.clock;
            room.alternating.deadTurnStarted=-1;
        }
    }
}
