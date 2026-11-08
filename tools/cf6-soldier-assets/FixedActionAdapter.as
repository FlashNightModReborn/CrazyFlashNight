// Native adapter for opt-in fixed personnel. Generic CF6 actors retain their AI.
cf6FixedInstall=function():Void {
    if(typeof this.cf6UnitIdentity!="string")return;
    this.cf6ActionApi=_global.org.flashNight.arki.scene.Cf6SoldierActions;
    this.cf6Signals=_global.org.flashNight.arki.scene.Cf6SoldierSignals;
    this.cf6Groups=_global.org.flashNight.arki.scene.Cf6DamageGroups;
    this.cf6Pairs=_global.org.flashNight.arki.scene.Cf6SoldierPairs;
    this.cf6Loot=_global.org.flashNight.arki.scene.Cf6SoldierLoot;
    var record:Object=this.cf6ActionApi.register(this);
    this.cf6LegacyTick=this.soldierTick;this.cf6LegacyWalk=this.行走;
    this.cf6LegacyCancel=this.soldierCancelAttack;this.cf6LegacyState=this.状态改变;
    this.cf6LegacyCanAct=this.soldierCanAct;this.cf6LegacyBegin=this.soldierBeginAttack;
    this.cf6LegacyEliteBegin=this.eliteBeginAttack;this.cf6LegacyCharge=this.soldierBeginCharge;
    this.cf6LegacyFinish=this.soldierFinishAttack;this.cf6LegacyDrive=this.soldierDriveShooting;
    this.cf6LegacyReloadEnd=this.soldierReloadEnd;this.cf6LegacyEliteReloadEnd=this.eliteReloadEnd;
    this.cf6LegacyGrenadeBegin=this.soldierBeginGrenade;this.cf6LegacyGrenadeThrow=this.soldierThrowGrenade;
    this.cf6LegacyLongFire=this.长枪射击;this.cf6LegacyPistolFire=this.手枪射击;this.cf6LegacyOffFire=this.手枪2射击;
    this.soldierTick=this.cf6FixedTick;this.行走=this.cf6FixedWalk;
    this.soldierCancelAttack=this.cf6FixedCancelAttack;this.状态改变=this.cf6FixedState;
    this.soldierCanAct=this.cf6FixedCanAct;this.soldierBeginAttack=this.cf6FixedBeginAttack;
    this.eliteBeginAttack=this.cf6FixedBeginDual;this.soldierBeginCharge=this.cf6FixedBeginCharge;
    this.soldierFinishAttack=this.cf6FixedFinishAttack;
    this.soldierReloadEnd=this.cf6FixedReloadEnd;this.eliteReloadEnd=this.cf6FixedReloadEnd;
    this.soldierBeginGrenade=this.cf6FixedBeginThrow;this.soldierThrowGrenade=this.cf6FixedThrow;
    this.长枪射击=this.cf6FixedLongFire;this.手枪射击=this.cf6FixedPistolFire;this.手枪2射击=this.cf6FixedOffFire;
    this.cf6Observation={};this.cf6Command={};this.cf6Cadence={};
    this.cf6CurrentFireBit=0;this.cf6ExpectedPose="";this.cf6MoveStage=-1;this.cf6MoveCycle=-1;
    this.cf6PoseSwitch=false;this.cf6ReloadRequested="";this.cf6LastTerminal=0;
    if(record==null){this.cf6FixedError="missing fixed roster capability/identity";trace("[CF6_FIXED_ACTION_ERROR] "+this.cf6FixedError);return;}
    this.cf6Profile=record.profile;
    var suppression:Object=this.cf6Profile.program.suppression;
    if(suppression!=null && (this.长枪.name!==suppression.weaponName
        || _root.getItemData(this.长枪.name).weapontype!==suppression.weaponType)){
        this.cf6FixedError="machinegun profile does not match actual weapon";return;
    }
    this.cf6ActionState=this.cf6RuleCreate(this.cf6ActionApi.context().key,record.key,this.version);
    this.soldierTuning.shootRange=record.profile.program.maxDistance;
    this.soldierTuning.keepDistance=record.profile.program.stopDistance;
    this.soldierTuning.laneRange=record.profile.program.lane;
    this.cf6StrideStep=0;this.cf6NavStalls=0;this.cf6NavRetry=0;this.cf6NavPlans=0;
    this.cf6Ground=_global.org.flashNight.arki.spatial.move.Mover;
    this.cf6Collision=_global.org.flashNight.arki.collision.CollisionLayerRenderer;
    this.dispatcher.subscribe("hit",this.cf6FixedHit,this);
    this.dispatcher.subscribe("death",this.cf6FixedDeath,this);
};
cf6FixedHit=function(target:MovieClip,shooter:MovieClip,bullet:Object,collision:Object,result:Object):Void {
    if(target!==this || !(this.hp>0) || shooter==null || shooter===this)return;
    this.cf6Signals.event(this,"damage");
    if(this.soldierPhase==1 && this.soldierShieldGuardActive)this.cf6GuardImpactPending=true;
};
cf6FixedDeath=function():Void {
    if(this.cf6ActionState==null || this.soldierPhase!=2 || this.hp>0 || this.cf6ActionRecord.combatDead)return;
    // Capture before the canonical death event unloads children/equipment.
    if(typeof this.cf6Loot.combatDeath=="function")this.cf6Loot.combatDeath(this);
    this.cf6Signals.event(this,"death");this.cf6FixedCancel("death");
};
cf6FixedRelease=function():Void {
    if(this.cf6ActionState==null)return;
    this.cf6FixedCancel("unload");
    if(this.cf6ActionRecord!=null)this.cf6ActionRecord.retired=true;
};
cf6FixedState=function(next:String):Void {
    if(!this.cf6PoseSwitch && this.cf6ActionState!=null
        && !(_root.控制目标==this._name && _root.控制目标全自动==false)){
        // An AI attack request arriving outside the fixed program would create
        // a legacy shooting owner that the fixed action clock cannot advance.
        if(next=="长枪攻击" || next=="投掷手雷")return;
        if(this.soldierAttackOwner.fixed && this.soldierAttackOwner.active
            && (next=="长枪站立" || next=="长枪行走" || next=="长枪跑"))return;
    }
    if(!this.cf6PoseSwitch && next!=this.状态)this.cf6FixedCancel("state_changed");
    this.cf6LegacyState(next);
};
cf6FixedCancelAttack=function():Void {
    if(!this.cf6PoseSwitch && !this.cf6Cancelling)this.cf6FixedCancel("native_cancel");
    this.cf6LegacyCancel();
};
cf6FixedCancel=function(reason:String):Void {
    if(this.cf6ActionState==null || this.cf6Cancelling)return;
    this.cf6Cancelling=true;
    this.cf6Observation.frame=this.cf6ActionApi.now();
    this.cf6RuleCancel(this.cf6ActionState,this.cf6Profile,this.cf6Observation,reason);
    this.cf6ActionApi.end(this.cf6ActionRecord);
    this.cf6LegacyCancel();this.cf6CurrentFireBit=0;
    this.cf6FixedRestoreCharge();
    this.cf6Cancelling=false;
};
cf6FixedPermitExpired=function():Void {
    this.cf6RuleConsumeTrigger(this.cf6ActionState,this.cf6Observation);
    if(this.cf6ActionState.active)this.cf6FixedCancel("permit_expired");
    else this.cf6ActionState.readyAt=Math.max(this.cf6ActionState.readyAt,this.cf6ActionApi.now()+this.cf6Profile.program.recovery);
};
cf6FixedCanAct=function(body:MovieClip):Boolean {
    var owner:Object=this.soldierAttackOwner;
    if(!owner.fixed)return this.cf6LegacyCanAct(body);
    return !_root.暂停 && this.hp>0 && this.soldierPhase==owner.phase && this.soldierPhase>0
        && !this.倒地 && !this.浮空 && body===this.man && body.soldierToken===owner.token
        && owner.active && owner.version===this.version && owner.weapon===this.长枪
        && owner.pistol===this.手枪 && owner.sidearm===this.手枪2
        && (owner.mode=="throw"?this.状态=="投掷手雷":this.状态=="长枪攻击");
};
cf6FixedOwner=function(body:MovieClip,mode:String):Object {
    var token:Object={};body.soldierToken=token;
    var owner:Object={fixed:true,token:token,active:true,version:this.version,phase:this.soldierPhase,
        weapon:this.长枪,pistol:this.手枪,sidearm:this.手枪2,target:this.攻击目标,
        mode:mode,action:"shoot",kind:mode=="dual"?"retreat":"stand",elite:mode=="dual",
        age:0,poseAge:0,reload:false,shots:0,sidearmShots:0,fireDeadline:100000000,
        cycle:this.cf6ActionState.cycle,startedAt:this.soldierClock};
    this.soldierAttackOwner=owner;return owner;
};
cf6FixedBeginAttack=function(body:MovieClip,action:String):Void {
    if(this.cf6ExpectedPose!="primary" && this.cf6ExpectedPose!="sub"){
        this.cf6LegacyBegin(body,action);return;
    }
    var owner:Object=this.cf6FixedOwner(body,this.cf6ExpectedPose);
    body.初始化长枪射击函数=_root.主角函数.初始化长枪射击函数;body.初始化长枪射击函数();
    this.soldierWrapReloadCommit(body);
    body.gotoAndStop("空闲");
};
cf6FixedBeginDual=function(body:MovieClip):Void {
    if(this.cf6ExpectedPose!="dual"){this.cf6LegacyEliteBegin(body);return;}
    var owner:Object=this.cf6FixedOwner(body,"dual");
    body.初始化长枪射击函数=_root.主角函数.初始化长枪射击函数;
    body.初始化混合双枪=_root.主角函数.初始化混合双枪;
    body.开始混合手枪换弹=_root.主角函数.开始混合手枪换弹;
    body.混合手枪换弹匣=_root.主角函数.混合手枪换弹匣;
    body.初始化长枪射击函数();body.初始化混合双枪();
    body.prepareStandardShotPose=function(frame:String):Void {
        var owner:Object=this._parent.soldierAttackOwner;
        owner.recoilUntil=owner.poseAge+2;owner.recoilWeapon=frame=="射击2"?"secondary":"primary";
    };
    body.腰挂.syncHolsters();body.gotoAndStop(21);
};
cf6FixedBeginCharge=function(body:MovieClip):Void {
    this.cf6PoseSwitch=true;this.cf6LegacyCharge(body);this.cf6PoseSwitch=false;
    var owner:Object=this.soldierAttackOwner;
    if(this.cf6ExpectedPose!="charge" || owner==null)return;
    owner.fixed=true;owner.mode="charge";owner.phase=this.soldierPhase;
    owner.pistol=this.手枪;owner.sidearm=this.手枪2;owner.shotLimit=0;
    this.cf6ChargeOldMax=this.soldierTacticalConfig.chargeMaxDistance;
    this.cf6ChargeOldTurns=this.soldierTacticalConfig.chargeMaxTurns;
    this.soldierTacticalConfig.chargeMaxDistance=this.cf6Profile.program[this.cf6ActionState.variant][this.cf6ActionState.index].distance;
    this.soldierTacticalConfig.chargeMaxTurns=0;
};
cf6FixedRestoreCharge=function():Void {
    if(this.cf6ChargeOldMax!=undefined){
        this.soldierTacticalConfig.chargeMaxDistance=this.cf6ChargeOldMax;
        this.soldierTacticalConfig.chargeMaxTurns=this.cf6ChargeOldTurns;
        delete this.cf6ChargeOldMax;delete this.cf6ChargeOldTurns;
    }
};
cf6FixedFinishAttack=function(body:MovieClip):Void {
    var owner:Object=this.soldierAttackOwner;
    if(!owner.fixed){
        if(owner.bash && owner.meleeCommitted && this.soldierPhase==1 && body===this.man && body.soldierToken===owner.token)
            this.cf6Signals.event(this,"shield");
        this.cf6LegacyFinish(body);return;
    }
    if(!this.cf6FixedCanAct(body))return;
    if(owner.mode=="charge"){
        if(owner.distance<.1 && owner.blockedFrames>0){this.cf6FixedCancel("charge_blocked");return;}
        this.cf6Signals.event(this,"charge");this.cf6FixedRestoreCharge();
    }
    this.cf6PoseSwitch=true;this.cf6LegacyFinish(body);this.cf6PoseSwitch=false;
};
cf6FixedEnsurePose=function(mode:String):Void {
    var owner:Object=this.soldierAttackOwner;
    if(owner.fixed && owner.mode==mode && this.cf6FixedCanAct(this.man))return;
    if(owner.fixed && (owner.mode=="primary" || owner.mode=="sub") && (mode=="primary" || mode=="sub")
        && this.cf6FixedCanAct(this.man)){
        owner.mode=mode;this.cf6ExpectedPose=mode;return;
    }
    if(mode=="none" || mode=="")return;
    this.cf6PoseSwitch=true;this.cf6ExpectedPose=mode;
    this.方向改变(this.cf6Observation.faceSign<0?"左":"右");
    this.cf6LegacyCancel();
    this.eliteNextAction=mode=="dual"?"retreat":mode=="charge"?"stand":"line";
    this.soldierShieldCoverFire=mode!="charge";
    // A stopped root with the same logical state still needs a genuine new man
    // when changing weapon modes. No action counters live on that man.
    this.状态="";this.cf6LegacyState(mode=="throw"?"投掷手雷":"长枪攻击");
    this.cf6PoseSwitch=false;
};
cf6FixedDrivePose=function():Void {
    var owner:Object=this.soldierAttackOwner,body:MovieClip=this.man;
    if(!owner.fixed || !this.cf6FixedCanAct(body) || owner.reload)return;
    owner.age++;owner.poseAge++;
    if(owner.mode=="dual"){
        var frame:Number=21;
        if(body._currentframe!=frame)body.gotoAndStop(frame);
        if(body.枪2!=null)body.枪2._visible=true;
        if(owner.recoilUntil>owner.poseAge)this.eliteApplyRecoil(body);
    }
    if(owner.mode=="throw"){
        var throwFrame:Number=Math.min(24,owner.poseAge+1);
        if(body._currentframe!=throwFrame)body.gotoAndStop(throwFrame);
    }
};
cf6FixedModeReady=function(mode:String):Boolean {
    var owner:Object=this.soldierAttackOwner,body:MovieClip=this.man;
    if(!owner.fixed || owner.mode!=mode || owner.reload || !this.cf6FixedCanAct(body))return false;
    if(mode=="throw")return body.投掷手!=null;
    if(mode=="dual")return this.elitePistolMuzzleMarker(body,"手枪")!=null
        && this.elitePistolMuzzleMarker(body,"手枪2")!=null;
    return this.soldierMuzzleMarker(body)!=null;
};
cf6FixedWalkPose=function(sign:Number,moving:Boolean,running:Boolean,travelSign:Number):Void {
    this.cf6PoseSwitch=true;this.cf6ExpectedPose="";
    var facing:String=sign<0?"左":"右";
    if(this.方向!==facing || this._xscale!=sign*this.myxscale
        || this.新版人物文字信息!=null && this.新版人物文字信息._xscale!=sign*100)this.方向改变(facing);
    var desired:String=moving?(running?"长枪跑":"长枪行走"):"长枪站立";
    if(this.状态!==desired)this.cf6LegacyState(desired);
    // Root facing is AI state (including shield-breach eligibility). Mirror
    // only the current body around the actor origin for a running detour.
    // These six roots author man with positive X scale and pivot offset.
    var body:MovieClip=this.man;
    if(body._xscale!=undefined){
        var bodySign:Number=running && moving && travelSign*sign<0?-1:1;
        body._xscale=Math.abs(body._xscale)*bodySign;
        body._x=Math.abs(body._x)*bodySign;
    }
    this.cf6PoseSwitch=false;
};
cf6FixedMove=function(c:Object):Void {
    var s:Object=this.cf6ActionState,o:Object=this.cf6Observation;
    if(c.stageChanged)return;
    if(this.cf6MoveCycle!=s.cycle || this.cf6MoveStage!=s.index){
        this.cf6MoveCycle=s.cycle;this.cf6MoveStage=s.index;
        this.cf6MoveSign=o.faceSign;this.cf6MoveZ=this.soldierEvasionZSign();
        this.cf6MoveBlocked=false;
        if(c.moveDirection=="away")this.cf6Signals.event(this,"retreat");
    }
    var remaining:Number=Math.max(0,c.moveBudget-s.stageMoved);
    var amount:Number=Math.min(remaining,c.moveBudget/c.moveFrames);
    var direction:String=c.moveDirection;
    var sign:Number=direction=="away"?-this.cf6MoveSign:this.cf6MoveSign;
    if(direction=="lane")sign=this.cf6MoveZ;
    var beforeX:Number=this._x,beforeZ:Number=this.Z轴坐标;
    var tether:Number=this.cf6Profile.program.tether;
    var anchor:Number=this.cf6Profile.program.waiting=="boss_guard"?o.guardX:this.cf6ActionRecord.birthX;
    if(direction!="lane")amount=Math.min(amount,Math.max(0,tether-sign*(this._x-anchor)));
    if(amount>0)this.soldierTacticalMove(direction=="lane"?(sign<0?"上":"下"):(sign<0?"左":"右"),amount);
    var moved:Number=Math.abs(this._x-beforeX)+Math.abs(this.Z轴坐标-beforeZ);
    s.stageMoved+=moved;this.cf6MoveBlocked=moved<.1 && remaining>.1;
    this.cf6FixedWalkPose(this.cf6MoveSign,moved>.1);
};
cf6FixedWalk=function():Void {
    if(_root.控制目标==this._name && _root.控制目标全自动==false)this.cf6LegacyWalk();
    // Fixed AI movement runs on its continuous actor tick. The root walk tag
    // must not move it a second time.
};
cf6FixedTryMelee=function():Boolean {
    var o:Object=this.cf6Observation;
    if(this.cf6ActionState.active || this.soldierAttackOwner!=null || o.interrupted || o.controlled
        || !o.targetValid || !o.sameLane || o.distance>this.soldierTuning.knifeRange
        || this.soldierClock<this.soldierNextMeleeAt || this.soldierIsElite && !this.soldierIsInstructor)return false;
    this.soldierMeleeKind=this.soldierPhase==1 && o.distance<=this.soldierTuning.bashRange
        && this.soldierClock>=this.soldierNextBashAt?"bash":"knife";
    this.cf6ExpectedPose="";this.方向改变(o.faceSign<0?"左":"右");this.状态改变("近战");return true;
};
// Follow the same separation as player move-and-shoot: movement consumes
// collision-resolved inputs every frame, firing keeps its body and muzzle.
cf6FixedTrack=function(armed:Boolean):Void {
    var o:Object=this.cf6Observation,p:Object=this.cf6Profile.program;
    if(o.interrupted || o.controlled || !o.targetValid)return;
    var target:MovieClip=_root.gameworld[this.攻击目标];
    var dx:Number=target._x-this._x,dz:Number=target.Z轴坐标-this.Z轴坐标;
    var sign:Number=dx<0?-1:1,dist:Number=Math.abs(dx);
    var stop:Number=Math.max(60,Math.min(p.stopDistance,p.maxDistance-24));
    // Firing reach does not stop the advance. Preserve the occupied side
    // and approach the weapon's own preferred range, including during a burst.
    var closeAt:Number=this.cf6Profile.roleClass=="instructor" && this.cf6ActionState.variant!="pressure"?p.maxDistance:stop+36;
    if(dist>closeAt || !o.visible)this.cf6Closing=true;
    if(dist<=stop)this.cf6Closing=false;
    var goalX:Number=this._x,goalZ:Number=target.Z轴坐标;
    if(this.cf6Closing)goalX=target._x-sign*stop;
    else if(this.soldierPhase==2 && p.trigger=="ordinary" && stop>=240 && dist<stop*.55 && o.visible)
        goalX=target._x-sign*stop*.7;
    if(!o.visible && dist>96)goalX=target._x-sign*Math.min(stop,dist-48);
    var waypoint:Object=this.cf6NavWaypoint(target,o,stop);
    if(waypoint!=null){
        goalX=waypoint.x;goalZ=waypoint.z;
    }else if(o.flank!=null){
        goalX=target._x+o.flank.side*o.flank.distance;
        if((this._x-target._x)*o.flank.side<64)goalZ=target.Z轴坐标+o.flank.laneSign*48;
    }
    goalX=Math.max(_root.Xmin,Math.min(_root.Xmax,goalX));
    goalZ=Math.max(_root.Ymin,Math.min(_root.Ymax,goalZ));
    var run:Boolean=!armed && Math.abs(goalX-this._x)>160;
    var speedX:Number=run?this.跑X速度:this.行走X速度;
    var speedZ:Number=run?this.跑Y速度:this.行走Y速度;
    var xSign:Number=goalX<this._x?-1:1;
    dz=goalZ-this.Z轴坐标;
    var moveX:Number=Math.min(speedX,Math.abs(goalX-this._x));
    var moveZ:Number=Math.min(speedZ,Math.max(0,Math.abs(dz)-(waypoint!=null?0:Math.min(6,p.lane))));
    var x0:Number=this._x,z0:Number=this.Z轴坐标;
    if(moveX>0)this.soldierTacticalMove(xSign<0?"左":"右",moveX);
    if(moveZ>0)this.soldierTacticalMove(dz<0?"上":"下",moveZ);
    var stuckX:Boolean=moveX>.1 && Math.abs(this._x-x0)<.1;
    var stuckZ:Boolean=moveZ>.1 && Math.abs(this.Z轴坐标-z0)<.1;
    if(stuckX || stuckZ || o.obstructed)this.cf6NavStalls++;else this.cf6NavStalls=0;
    // A chosen elbow owns movement to its corner. A short local sidestep
    // remains available while a complex shared route is being prepared.
    if(waypoint==null && stuckX && Math.abs(this.Z轴坐标-z0)<.1){
        if(this.cf6SkirtSign!=1 && this.cf6SkirtSign!=-1)this.cf6SkirtSign=this.soldierEvasionZSign()<0?-1:1;
        if(this.soldierTacticalMove(this.cf6SkirtSign<0?"上":"下",speedZ)<.1)this.cf6SkirtSign=-this.cf6SkirtSign;
    }else if(waypoint==null && stuckZ && moveX<=0){
        if(this.soldierTacticalMove(sign<0?"左":"右",speedX)<.1)this.soldierTacticalMove(sign<0?"右":"左",speedX);
    }
    var travelled:Number=Math.abs(this._x-x0)+Math.abs(this.Z轴坐标-z0);
    this.standardShotMoving=travelled>.1;
    if(!armed){
        // Keep target-facing logic; only the running body's display follows
        // collision-resolved travel. Walking and firing keep their old pose.
        var travelledX:Number=this._x-x0;
        var travelSign:Number=run && Math.abs(travelledX)>.1?(travelledX<0?-1:1):sign;
        this.cf6FixedWalkPose(sign,travelled>.1,run,travelSign);return;
    }
    var legs:MovieClip=this.man.cf6Stride;
    if(legs!=null){
        if(travelled>.1)this.cf6StrideStep=(this.cf6StrideStep+1)%(legs._totalframes-1);
        var desiredFrame:Number=travelled>.1?2+this.cf6StrideStep:1;
        if(legs._currentframe!=desiredFrame)legs.gotoAndStop(desiredFrame);
    }
};
cf6FixedIdleMove=function():Void {
    if(this.soldierAttackOwner==null)this.cf6FixedTrack(false);
};
cf6FixedTick=function():Void {
    if(_root.暂停)return;
    if(this.cf6FixedError!=undefined){this.cf6LegacyCancel();this.soldierClearMovement();return;}
    var target:MovieClip=_root.gameworld[this.攻击目标];
    this.cf6ActionApi.observe(this.cf6ActionRecord,target,this.cf6Observation);
    if(this.soldierPhase==0 || !(this.hp>0)){
        if(!(this.hp>0))this.cf6FixedDeath();
        this.cf6FixedCancel("phase_or_death");this.cf6LegacyTick();return;
    }
    this.soldierClock++;this.soldierTacticalObserve();this.soldierClearMovement();
    this.soldierObserveShieldThreat();
    if(this.soldierTryShieldGuard())return;
    var owner:Object=this.soldierAttackOwner;
    if(owner.fixed && owner.reload){
        if(!this.cf6FixedCanAct(this.man)){this.cf6FixedCancel("reload_interrupted");return;}
        if(this.cf6Profile.program.trigger=="relocate_then_flush")this.cf6FixedMoveReload(owner);
        else if(owner.elite)this.soldierMoveSmokeReload(owner,this.man);
        _root.主角函数.换弹帧率控制(this.man);return;
    }
    // Let the real reload start before selecting a fresh attack on an empty gun.
    if(!this.cf6ActionState.active && !this.cf6Observation.controlled)this.cf6FixedIdleReload();
    if(this.cf6ReloadRequested!=""){
        this.cf6FixedReload(this.cf6ReloadRequested);return;
    }
    if(!this.cf6ActionState.active && this.cf6Pairs.assembly(this.cf6ActionRecord))return;
    if(this.cf6FixedTryMelee())return;
    this.cf6FixedDrivePose();
    var o:Object=this.cf6Observation,s:Object=this.cf6ActionState,c:Object=this.cf6Command;
    var stage:Object=s.active?this.cf6Profile.program[s.variant][s.index]:null;
    o.modeReady=stage!=null?this.cf6FixedModeReady(stage.mode):false;
    o.readyMode=owner.fixed?owner.mode:"none";
    o.moveBlocked=this.cf6MoveBlocked===true && s.cycle==this.cf6MoveCycle && s.index==this.cf6MoveStage;
    this.cf6RuleStep(s,this.cf6Profile,o,c);
    if(c.requestPermit){this.cf6ActionApi.request(this.cf6ActionRecord);this.cf6FixedIdleMove();return;}
    if(c.release || s.terminal!=this.cf6LastTerminal){
        this.cf6LastTerminal=s.terminal;this.cf6ActionApi.end(this.cf6ActionRecord);
        if(!o.interrupted && !o.controlled)this.cf6FixedWalkPose(o.faceSign,false);return;
    }
    if(c.stageChanged)return;
    if(!s.active){this.cf6FixedIdleMove();return;}
    if(c.kind=="recover" || c.kind=="wait" || c.kind=="projectile_wait" || c.kind=="mode_hold"){
        if(c.kind=="recover")this.cf6ActionApi.recovering(this.cf6ActionRecord);
        if(this.soldierAttackOwner.mode!="throw"){
            if(this.soldierAttackOwner!=null)this.cf6FixedWalkPose(o.faceSign,false);
            this.cf6FixedIdleMove();
        }
        return;
    }
    if(c.kind=="move"){this.cf6FixedMove(c);return;}
    if(c.kind=="charge"){
        this.cf6FixedEnsurePose("charge");
        if(this.soldierAttackOwner.charge)this.cf6LegacyDrive(this.man);return;
    }
    this.cf6FixedEnsurePose(c.mode);
    if(c.mode=="primary" || c.mode=="sub" || c.mode=="dual")this.cf6FixedTrack(true);
    if(c.warning)this.方向改变(s.aimSign<0?"左":"右");
    if(c.fireMask)this.cf6FixedFire(c.fireMask);
};
