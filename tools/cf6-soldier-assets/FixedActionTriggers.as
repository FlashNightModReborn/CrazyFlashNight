// Pure fixed158 trigger selection. Inputs are receipts supplied by the adapter.
// No MovieClip, clock, RNG, inventory or global access is permitted here.
cf6RuleSelect=function(s:Object,p:Object,o:Object):String {
    var a:Object=p.program,t:String=a.trigger;
    if(o.alternatingMember && !o.pairTurn)return "";
    if(!o.targetValid || !o.visible || !o.lineClear || !o.sameLane || o.distance>a.maxDistance || o.height>120)return "";
    if(t=="ordinary"){
        if(a.grenade!=null && s.throwUsed<p.extensions.finiteThrowableCount && o.distance>=180
            && o.distance<=480 && o.frame>=90 && o.throwReady)return "grenade";
        if(o.phase==1 && a.shield!=null && o.distance>=180 && o.distance<=240)return "shield";
        if(o.phase==2 && a.dual!=null && (p.role=="dual" || p.strategy=="mobile" && o.distance<280))return "dual";
        return "stages";
    }
    if(t=="shield_breach")return o.phase==2?"phase2":o.inFront && o.distance>=180?"stages":"";
    if(t=="reverse_rear_guard")return o.phase==2 && o.attackEvent>s.attackConsumed
        && o.attackAge<=30 && o.retreatAvailable?"stages":cf6RuleDefence(s,p,o);
    if(t=="fixed_bastion")return o.atAnchor?"stages":"";
    if(t=="pursuit_leash")return o.distance>180 && o.movingAway?"stages":"fallback";
    if(t=="advance_flush")return o.subReady && o.distance>=220?"stages":"fallback";
    if(t=="landing_watch")return o.wingsEvent>s.wingsConsumed && o.wingsRecovery?"stages":cf6RuleDefence(s,p,o);
    if(t=="relocate_then_flush")return o.reloadEvent>s.reloadConsumed && o.primaryLoaded && o.distance>=220?"stages":"";
    if(t=="shield_counter")return o.phase==1 && o.shieldEvent>s.shieldConsumed && o.subReady
        && o.distance>=180?"stages":"fallback";
    if(t=="judgment_line" || t=="disciplined_screen"){
        if(o.phase==2)return o.distance<=420?"dual":"";
        return o.pairEligible && o.fixedModeValid && o.distance>=a.minDistance?"stages":"";
    }
    if(t=="feint_retreat")return o.phase==2 && o.approaching && o.subReady?"stages":"fallback";
    if(t=="punish_commit")return o.phase==2 && o.commitEvent>s.commitConsumed && o.commitAge<=30
        && o.distance>=180?"stages":cf6RuleDefence(s,p,o);
    if(t=="paired_windows")return o.pairTurn?"stages":"";
    if(t=="reserve_gate")return o.atAnchor && o.reserveEvent>s.reserveConsumed?"stages":cf6RuleDefence(s,p,o);
    if(t=="robot_observer")return o.robotRecovery && o.robotEvent>s.robotConsumed?"stages":cf6RuleDefence(s,p,o);
    if(t=="threshold_flush")return !s.boundaryDisabled && o.crossEvent>s.crossConsumed
        && o.distance>=220?"stages":cf6RuleDefence(s,p,o);
    if(t=="final_phase_guard")return o.humanGuardValid && o.guardThreat
        ?(o.phase==2?"phase2":"stages"):"";
    if(t=="segmented_lane" || t=="bright_burst" || t=="range_rotation"
        || t=="alternating_fire" || t=="weapon_handoff")return "stages";
    return "";
};
cf6RuleDefence=function(s:Object,p:Object,o:Object):String {
    return o.phase==2 && p.program.dual!=null && o.distance<=120?"dual":"";
};
cf6RuleConsumeTrigger=function(s:Object,o:Object):Void {
    // Consumed once at attempt start, including interrupted/cancelled attempts.
    s.attackConsumed=Math.max(s.attackConsumed,o.attackEvent);
    s.shieldConsumed=Math.max(s.shieldConsumed,o.shieldEvent);
    s.wingsConsumed=Math.max(s.wingsConsumed,o.wingsEvent);
    s.reloadConsumed=Math.max(s.reloadConsumed,o.reloadEvent);
    s.commitConsumed=Math.max(s.commitConsumed,o.commitEvent);
    s.reserveConsumed=Math.max(s.reserveConsumed,o.reserveEvent);
    s.robotConsumed=Math.max(s.robotConsumed,o.robotEvent);
    s.crossConsumed=Math.max(s.crossConsumed,o.crossEvent);
};
cf6RuleStageEligible=function(stage:Object,o:Object):Boolean {
    if(stage.minDistance!=undefined && o.distance<stage.minDistance)return false;
    if(stage.maxDistance!=undefined && o.distance>stage.maxDistance)return false;
    if(stage.approaching===true && !o.approaching)return false;
    if(stage.mode=="sub" && !o.subReady)return false;
    return true;
};
