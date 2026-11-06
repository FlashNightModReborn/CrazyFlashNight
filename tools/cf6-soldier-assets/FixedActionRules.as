// Same-source, allocation-free per-tick action interpreter. Adapter callbacks
// only acknowledge real commits; changing a pose never creates a new budget.
cf6RuleCreate=function(world:String,birth:String,actorVersion:Number):Object {
    return {world:world,birth:birth,actorVersion:actorVersion,cycle:0,active:false,
        phase:0,index:0,entered:0,readyAt:0,variant:"",stageStarted:false,
        primary:0,left:0,right:0,sub:0,throwUsed:0,damageUnits:0,
        stagePrimary:0,stageLeft:0,stageRight:0,stageSub:0,stageThrow:0,
        nextPrimary:0,nextLeft:0,nextRight:0,nextSub:0,nextThrow:0,
        attackConsumed:0,shieldConsumed:0,wingsConsumed:0,reloadConsumed:0,
        commitConsumed:0,reserveConsumed:0,robotConsumed:0,crossConsumed:0,
        boundaryDisabled:false,targetKey:"",targetVersion:0,locked:false,
        aimX:0,aimY:0,aimZ:0,aimSign:1,warningSeen:0,lastFrame:-1,
        commitFrame:-1,commitMask:0,terminal:0,cancelReason:"",firstShot:-1,
        stageMoved:0,modeSince:0,stageBeginFrame:0,chargeSerial:0};
};
cf6RuleResetOutput=function(c:Object):Void {
    c.kind="idle";c.mode="none";c.fireMask=0;c.warning=false;c.locked=false;
    c.requestPermit=false;c.release=false;c.started=false;c.stageChanged=false;
    c.moveDirection="";c.moveBudget=0;c.moveFrames=0;c.cycle=0;c.stage=0;
};
cf6RuleCancel=function(s:Object,p:Object,o:Object,reason:String):Void {
    if(!s.active)return;
    s.active=false;s.commitMask=0;s.commitFrame=-1;s.terminal++;
    var recovery:Number=p.program.recovery;
    if(s.firstShot<0)recovery=2;
    else if(o.recoveryFloor>recovery)recovery=o.recoveryFloor;
    s.cancelReason=reason;s.readyAt=Math.max(s.readyAt,o.frame+recovery);
};
cf6RuleEnter=function(s:Object,o:Object):Void {
    s.entered=o.frame;s.stageBeginFrame=o.frame;s.stageStarted=false;
    s.stagePrimary=0;s.stageLeft=0;s.stageRight=0;s.stageSub=0;s.stageThrow=0;
    s.stageMoved=0;s.warningSeen=0;
};
cf6RuleAdvance=function(s:Object,p:Object,o:Object,c:Object):Void {
    s.index++;c.stageChanged=true;s.commitMask=0;
    if(s.index>=p.program[s.variant].length){
        s.active=false;s.terminal++;s.cancelReason="complete";s.readyAt=Math.max(s.readyAt,o.frame);
        c.release=true;return;
    }
    cf6RuleEnter(s,o);
};
cf6RuleStart=function(s:Object,p:Object,o:Object,variant:String,c:Object):Void {
    s.cycle++;s.active=true;s.variant=variant;s.index=0;s.phase=o.phase;
    s.primary=0;s.left=0;s.right=0;s.sub=0;s.damageUnits=0;s.firstShot=-1;
    s.targetKey=o.targetKey;s.targetVersion=o.targetVersion;s.locked=false;
    s.modeSince=o.frame;s.chargeSerial=o.chargeTerminal;s.cancelReason="";
    if(variant!="pressure")cf6RuleConsumeTrigger(s,o);
    s.needsPermit=cf6RuleNeedsPermit(p,o,variant);
    cf6RuleEnter(s,o);c.started=true;
};
cf6RuleNeedsPermit=function(p:Object,o:Object,variant:String):Boolean {
    if(variant!="pressure")return p.program.danger || o.forcePermit;
    var budget:Object=p.budget;
    return o.forcePermit || budget.primarySplit>1 || budget.primaryFinalDamageUnitsPerAction>budget.primaryTriggerLimit;
};
cf6RulePressureReady=function(p:Object,o:Object):Boolean {
    return p.program.pressure!=null && o.primaryLoaded && !o.reloadHidden && (p.roleClass!="instructor" || o.pressureReady===true) && o.targetValid && o.sameLane
        && o.visible && o.lineClear && o.distance<=p.program.fireDistance && o.height<=120
        && (!o.alternatingMember || o.pairTurn) && o.pairEligible!==false;
};
cf6RuleStep=function(s:Object,p:Object,o:Object,c:Object):Void {
    cf6RuleResetOutput(c);
    if(o.paused || o.frame<=s.lastFrame)return;
    s.lastFrame=o.frame;s.commitMask=0;s.commitFrame=-1;
    if(o.behindBirth)s.boundaryDisabled=true;
    var a:Object=p.program;
    if(s.active && (o.world!=s.world || o.birth!=s.birth || o.actorVersion!=s.actorVersion
        || !o.alive || o.retired || o.controlled || o.phase!=s.phase || o.interrupted)){
        cf6RuleCancel(s,p,o,"actor_changed");c.release=true;return;
    }
    if(!s.active){
        if(!o.alive || o.retired || o.interrupted || o.controlled || o.phase==0 || o.frame<s.readyAt
            || o.world!=s.world || o.birth!=s.birth || o.actorVersion!=s.actorVersion)return;
        var selected:String=cf6RuleSelect(s,p,o);
        var pressure:Boolean=cf6RulePressureReady(p,o);
        if(selected=="" && pressure)selected="pressure";
        if(selected=="")return;
        if(cf6RuleNeedsPermit(p,o,selected) && !o.permit){
            c.requestPermit=true;
            // The first request gets its normal turn. While another hazard is
            // actually occupying the lane the soldier may use ordinary rounds.
            if(!pressure || !o.hazardOccupied || cf6RuleNeedsPermit(p,o,"pressure"))return;
            selected="pressure";c.requestPermit=false;
        }
        cf6RuleStart(s,p,o,selected,c);
    }
    c.cycle=s.cycle;c.stage=s.index;
    var stage:Object=a[s.variant][s.index],kind:String=stage.kind;
    c.kind=kind;c.mode=stage.mode;
    if(kind=="recover"){
        var restFrames:Number=stage.frames;
        if(o.recoveryFloor>restFrames)restFrames=o.recoveryFloor;
        if(o.frame-s.entered>=restFrames)cf6RuleAdvance(s,p,o,c);
        return;
    }
    if(!o.targetValid || o.targetKey!=s.targetKey || o.targetVersion!=s.targetVersion || !o.visible || !o.lineClear
        || s.variant!="pressure" && a.trigger=="robot_observer" && !o.robotRecovery
        || s.variant!="pressure" && a.trigger=="landing_watch" && !o.wingsRecovery
        || s.variant!="pressure" && a.trigger=="threshold_flush" && s.boundaryDisabled
        || s.variant!="pressure" && a.trigger=="final_phase_guard" && (!o.humanGuardValid || !o.guardTether)
        || s.needsPermit && !o.permit
        || s.variant=="stages" && (a.trigger=="judgment_line" || a.trigger=="disciplined_screen")
            && (!o.pairEligible || !o.fixedModeValid || o.distance<a.minDistance || !o.sameLane)
        || o.distance>(s.variant=="pressure"?a.fireDistance:a.maxDistance)){
        cf6RuleCancel(s,p,o,"target_or_permission");c.release=true;return;
    }
    var completeFire:Boolean=kind=="fire" && (stage.mode=="primary" && s.stagePrimary>=stage.events
        || stage.mode=="dual" && s.stageLeft>=stage.events && s.stageRight>=stage.events
        || stage.mode=="sub" && s.stageSub>=stage.events || stage.mode=="throw" && s.stageThrow>=stage.events);
    if(completeFire){cf6RuleAdvance(s,p,o,c);return;}
    if(!cf6RuleStageEligible(stage,o)){
        if(stage.optional===true){s.index=a[s.variant].length-1;cf6RuleEnter(s,o);c.stageChanged=true;return;}
        cf6RuleCancel(s,p,o,"stage_predicate");c.release=true;return;
    }
    if((stage.mode=="sub" || stage.mode=="throw") && !o.subPermit){
        c.requestPermit=true;
        if(o.frame-s.stageBeginFrame>=180){cf6RuleCancel(s,p,o,"permit_expired");c.release=true;}
        return;
    }
    if(stage.mode!="none" && (!o.modeReady || o.readyMode!=stage.mode)){
        if(o.frame-s.stageBeginFrame>=60){cf6RuleCancel(s,p,o,"mode_not_ready");c.release=true;}
        return;
    }
    if(!s.stageStarted){
        s.stageStarted=true;s.entered=o.frame;
        if(kind=="warning")s.locked=false;
    }
    var age:Number=o.frame-s.entered;
    if(kind=="draw"){cf6RuleAdvance(s,p,o,c);return;}
    if(kind=="warning"){
        if(!s.locked){
            s.aimX=o.targetX;s.aimY=o.targetY;s.aimZ=o.targetZ;s.aimSign=o.faceSign;
            if(stage.lock>0 && age>=stage.frames-stage.lock)s.locked=true;
        }
        c.warning=true;c.locked=s.locked;s.warningSeen++;
        if(age>=stage.frames && s.warningSeen>=stage.frames+1){
            s.locked=true;cf6RuleAdvance(s,p,o,c);
        }
        return;
    }
    if(kind=="charge"){
        if(o.chargeTerminal>s.chargeSerial){cf6RuleAdvance(s,p,o,c);return;}
        if(age>=stage.frames || o.moveBlocked){cf6RuleCancel(s,p,o,"charge_no_terminal");c.release=true;}
        return;
    }
    if(kind=="move"){
        c.moveDirection=stage.direction;c.moveBudget=stage.distance;c.moveFrames=stage.frames;
        if(stage.pose!=undefined)c.mode=stage.pose;
        if(o.moveBlocked){cf6RuleCancel(s,p,o,"movement_blocked");c.release=true;return;}
        if(stage.stopDistance!=undefined && (stage.direction=="toward" && o.distance<=stage.stopDistance
            || stage.direction=="away" && o.distance>=stage.stopDistance)
            || s.stageMoved>=stage.distance || age>=stage.frames)cf6RuleAdvance(s,p,o,c);
        return;
    }
    if(kind=="projectile_wait"){
        if(o.projectilesTerminal){cf6RuleAdvance(s,p,o,c);return;}
        if(age>=stage.frames){cf6RuleCancel(s,p,o,"projectile_unknown");c.release=true;}
        return;
    }
    if(kind=="mode_hold"){
        if(o.frame-s.modeSince>=stage.frames)cf6RuleAdvance(s,p,o,c);
        return;
    }
    if(kind=="wait"){
        if(age>=stage.frames)cf6RuleAdvance(s,p,o,c);
        return;
    }
    if(kind!="fire"){cf6RuleCancel(s,p,o,"invalid_stage");c.release=true;return;}
    var mode:String=stage.mode,limit:Number=stage.events;
    if((mode=="primary" && s.stagePrimary>=limit) || (mode=="dual" && s.stageLeft>=limit && s.stageRight>=limit)
        || (mode=="sub" && s.stageSub>=limit) || (mode=="throw" && s.stageThrow>=limit)){
        cf6RuleAdvance(s,p,o,c);return;
    }
    if(age>=stage.frames){cf6RuleAdvance(s,p,o,c);return;}
    // No catch-up loop. At most one real event per slot in this active frame.
    if(mode=="primary" && s.stagePrimary<limit && o.frame>=s.nextPrimary)c.fireMask=1;
    if(mode=="dual"){
        if(s.stageLeft<limit && o.frame>=s.nextLeft)c.fireMask+=2;
        if(s.stageRight<limit && o.frame>=s.nextRight)c.fireMask+=4;
    }
    if(mode=="sub" && s.stageSub<limit && o.frame>=s.nextSub)c.fireMask=8;
    if(mode=="throw" && s.stageThrow<limit && o.frame>=s.nextThrow)c.fireMask=16;
    s.commitFrame=o.frame;s.commitMask=c.fireMask;
};
cf6RuleCanCommit=function(s:Object,p:Object,o:Object,bit:Number,units:Number):Boolean {
    if(!s.active || o.paused || !o.alive || !o.visible || !o.lineClear || o.interrupted || o.controlled || o.retired
        || o.frame!=s.commitFrame || (s.commitMask&bit)==0 || o.phase!=s.phase
        || o.world!=s.world || o.birth!=s.birth || o.actorVersion!=s.actorVersion
        || !o.targetValid || o.targetKey!=s.targetKey || o.targetVersion!=s.targetVersion
        || s.needsPermit && !o.permit || !o.modeReady
        || o.distance>(s.variant=="pressure"?p.program.fireDistance:p.program.maxDistance))return false;
    var stage:Object=p.program[s.variant][s.index],b:Object=p.budget;
    if(stage.kind!="fire" || o.readyMode!=stage.mode || !cf6RuleStageEligible(stage,o)
        || !isFinite(units) || units<1 || s.damageUnits+units>b.scriptedCycleDamageUnits)return false;
    if(bit==1 && (stage.mode!="primary" || s.primary>=b.primaryTriggerLimit))return false;
    if((bit==2 || bit==4) && (stage.mode!="dual" || (bit==2?s.left:s.right)>=b.sidearmSynchronizedTriggerLimit))return false;
    if(bit==8 && (stage.mode!="sub" || s.sub>=p.extensions.subweaponBurstLimit || !o.subPermit))return false;
    if(bit==16 && (stage.mode!="throw" || s.throwUsed>=p.extensions.finiteThrowableCount || !o.subPermit))return false;
    if(!p.program.mixed && ((bit==1 || bit==8) && (s.left>0 || s.right>0)
        || (bit==2 || bit==4) && (s.primary>0 || s.sub>0)))return false;
    return true;
};
cf6RuleCommitted=function(s:Object,p:Object,o:Object,bit:Number,units:Number):Void {
    // Called once immediately before the actual dispatch, after all gates pass.
    s.commitMask=s.commitMask&(~bit);s.damageUnits+=units;
    var gap:Number=p.program[s.variant][s.index].gap;
    if(!(gap>=1))gap=1;
    if(bit==1){s.primary++;s.stagePrimary++;s.nextPrimary=o.frame+gap;}
    if(bit==2){s.left++;s.stageLeft++;s.nextLeft=o.frame+gap;}
    if(bit==4){s.right++;s.stageRight++;s.nextRight=o.frame+gap;}
    if(bit==8){s.sub++;s.stageSub++;s.nextSub=o.frame+gap;}
    if(bit==16){s.throwUsed++;s.stageThrow++;s.nextThrow=o.frame+gap;}
    if(s.firstShot<0)s.firstShot=o.frame;
};
