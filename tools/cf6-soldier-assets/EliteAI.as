// Elite-only motion and mixed-weapon adapter. Ordinary soldiers keep their own controller.
soldierIsElite=true;
eliteActionCounts={stand:0,retreat:0,slide:0};eliteMoveFrames=0;eliteMoveDistance=0;
eliteCompletedActions=0;eliteInterruptedActions=0;eliteSidearmShotCount=0;
eliteAbstraction=String(this.特种兵精英消融);
eliteTactics=eliteAbstraction!="ordinary";
eliteMobility=eliteTactics && eliteAbstraction!="stationary";
eliteSidearmAllowed=eliteAbstraction!="noSidearm";
eliteSidearmReady=false;eliteSidearmError="";eliteWeaponCooldowns={};
eliteOriginalChoose=soldierChooseAttack;
eliteOriginalDrive=soldierDriveShooting;
eliteOriginalFire=长枪射击;
eliteOriginalBreak=soldierFinishBreak;
eliteOriginalBegin=soldierBeginAttack;
eliteOriginalTick=soldierTick;
eliteOriginalCanAct=soldierCanAct;
eliteOriginalStateChange=状态改变;
eliteNextAction="stand";eliteNextDodgeAt=0;eliteStrafeSign=1;

eliteUpdateName=function():Void {
    var next:String=this.soldierIsInstructor===true?(this.soldierPhase==1?"CF6特种教官·持盾":"CF6特种教官"):(this.soldierPhase==1?"CF6特种兵·持盾一阶段":"CF6特种精英·二阶段");
    if(typeof this.displayName=="string" && this.名字!=undefined)this.displayName=this.displayName.split(this.名字).join(next);
    this.名字=next;
};
eliteValidatePistol=function(slot:String):Boolean {
    var item:Object=this[slot],attrs:Object=this[slot+"属性"];
    return item!=null && item.value!=null && attrs!=null && attrs.interval>0
        && isFinite(attrs.interval) && attrs.capacity>0 && this[slot+"弹匣容量"]>0
        && typeof this[slot+"_装扮"]=="string" && this[slot+"_装扮"]!="";
};
elitePrimaryPistolEnabled=function():Boolean {
    return this.eliteTactics && this.eliteValidatePistol("手枪");
};
eliteValidateSidearm=function():Boolean {
    this.eliteSidearmReady=this.eliteValidatePistol("手枪2");
    this.eliteSidearmError=this.eliteSidearmReady?"":"Second pistol equipment, ammo data or dressup is unavailable";
    return this.eliteSidearmReady;
};
eliteSidearmEnabled=function():Boolean {
    return this.eliteTactics && this.eliteSidearmAllowed && this.eliteValidateSidearm();
};
eliteWeaponSlot=function(weapon:String):String {
    if(weapon=="secondary")return "手枪2";
    return this.soldierAttackOwner.kind=="retreat"?"手枪":"长枪";
};
eliteWeaponReady=function(slot:String):Boolean {
    var cooldown:Object=this.eliteWeaponCooldowns[slot];
    return cooldown==null || cooldown.weapon!==this[slot] || !(this.soldierClock<cooldown.readyAt);
};
eliteRecordWeaponShot=function(slot:String):Void {
    this.eliteWeaponCooldowns[slot]={weapon:this[slot],
        readyAt:this.soldierClock+Math.max(1,Math.ceil(this[slot+"属性"].interval*30/1000))};
};
eliteInitialize=function():Void {
    this.eliteUpdateName();
    this.eliteValidateSidearm();
};
soldierFinishBreak=function(body:MovieClip):Void {
    this.eliteOriginalBreak(body);
    if(this.soldierPhase==2)this.eliteUpdateName();
};
状态改变=function(next:String):Void {
    var charge:Object=this.soldierAttackOwner,config:Object=this.soldierTacticalConfig;
    if(next=="被击" && charge.charge && charge.age>=config.chargeWindupFrames
        && charge.age<config.chargeWindupFrames+config.chargeActiveFrames)return;
    if(this.soldierIsInstructor!==true && (next=="近战" || next=="投掷手雷"))next="长枪站立";
    this.elitePendingState=next;this.eliteOriginalStateChange(next);delete this.elitePendingState;
};
soldierCanAct=function(body:MovieClip):Boolean {
    var owner:Object=this.soldierAttackOwner;
    if(owner.charge)return !_root.暂停 && this.soldierPhase==1 && this.hp>0 && !this.倒地 && !this.浮空
        && owner.active && body===this.man && body.soldierToken===owner.token
        && owner.version===this.version && owner.weapon===this.长枪 && this.状态=="长枪攻击";
    if(!owner.elite)return this.eliteOriginalCanAct(body);
    return !_root.暂停 && this.soldierPhase!=0 && this.hp>0 && owner!=null && owner.active
        && body===this.man && body.soldierToken===owner.token && owner.version===this.version
        && owner.weapon===this.长枪 && owner.pistol===this.手枪 && owner.sidearm===this.手枪2 && this.状态=="长枪攻击";
};
soldierTick=function():Void {
    var owner:Object=this.soldierAttackOwner;
    if(!_root.暂停 && owner.elite && owner.kind=="stand" && !owner.reload && owner.age>=12
        && this.soldierCanAct(this.man)){
        var target:MovieClip=_root.gameworld[this.攻击目标];
        if(this.soldierTryEvasion(Math.abs(target._x-this._x),Math.abs(target.Z轴坐标-this.Z轴坐标))){
            // Preserve weapon cadence/ammunition; only this stationary action yields.
            this.soldierFinishAttack(this.man);return;
        }
    }
    if((owner.elite || owner.charge) && this.硬直中 && !this.倒地 && !this.浮空 && this.soldierCanAct(this.man)){
        this.soldierClock++;this.soldierDriveShooting(this.man);return;
    }
    this.eliteOriginalTick();
};
soldierCancelAttack=function():Void {
    var previous:Object=this.soldierAttackOwner;
    if(typeof this.soldierReleaseChargeObserver=="function")this.soldierReleaseChargeObserver();
    if(previous.charge && this.特种兵战术诊断===true && typeof _root.服务器.发布服务器消息=="function")
        _root.服务器.发布服务器消息("[CF6-CHARGE-ACTION] unit="+this._name+" age="+previous.age
            +" moved="+previous.distance+" movedZ="+previous.chargeMovedZ+" turns="+previous.turns
            +" shots="+previous.shots+" contact="+(previous.contactCommitted?1:0)+" hp="+this.hp);
    if(previous!=null && !previous.completed)this.soldierSlidePermit=null;
    if(previous.elite && previous.reload && typeof _root.主角函数.取消混合换弹=="function")
        _root.主角函数.取消混合换弹.call(this.man);
    if(previous.elite && previous.reload && this.man._currentframe>=previous.reloadEndFrame)previous.completed=true;
    if(previous.elite){
        if(previous.completed)this.eliteCompletedActions++;else this.eliteInterruptedActions++;
        if(this.特种兵精英诊断===true && typeof _root.服务器.发布服务器消息=="function"){
            _root.服务器.发布服务器消息("[CF6-ELITE-ACTION] unit="+this._name+" kind="+previous.kind
                +" completed="+(previous.completed?1:0)+" shots="+previous.shots+"/"+previous.shotLimit
                +" sidearm="+previous.sidearmShots+"/"+previous.sidearmShotLimit
                +" moved="+Math.round(this.eliteMoveDistance-previous.moveStart)+" age="+previous.age
                +" hp="+Math.round(this.hp)+" tough="+this.韧性系数+" state="+this.状态
                +" reload="+(previous.reload?1:0)+" slot="+previous.reloadSlot
                +" frame="+this.man._currentframe+" hard="+(this.硬直中?1:0)
                +" next="+this.elitePendingState+" version="+(previous.version===this.version?1:0)
                +" weapon="+(previous.weapon===this.长枪?1:0)+" sidearmObject="+(previous.sidearm===this.手枪2?1:0)
                +" token="+(this.man.soldierToken===previous.token?1:0));
        }
    }
    if(this.soldierAttackOwner!=null)this.soldierAttackOwner.active=false;
    this.soldierAttackOwner=null;this.动作A=false;this.动作B=false;
    delete this.standardShotMoving;
    _root.主角函数.清理射击任务(this,true);
};
soldierChooseAttack=function(dx:Number,dz:Number,height:Number):String {
    return this.soldierTacticalChoose(dx,dz,height);
};
eliteBeginReload=function(body:MovieClip,slot:String):Void {
    var owner:Object=this.soldierAttackOwner;
    if(owner==null || owner.reload)return;
    owner.reloadPair=owner.kind=="retreat" && slot!="长枪" && this.eliteSidearmEnabled()
        && this.手枪.value.shot>0 && this.手枪2.value.shot>0;
    owner.reload=true;owner.reloadSlot=owner.reloadPair?"手枪":slot;
    owner.reloadMainCommitted=false;owner.reloadOffCommitted=false;owner.reloadEndFrame=slot=="长枪"?295:owner.reloadPair?365:330;
    body.腰挂.syncHolsters();
    this.动作A=false;this.动作B=false;
    _root.主角函数.清理射击任务(this,true);
    if(slot=="手枪" || slot=="手枪2")body.开始混合手枪换弹(owner.reloadSlot);
    else body.开始换弹();
};
eliteBeginAttack=function(body:MovieClip):Void {
    var evasion:Object=this.soldierPendingEvasion;this.soldierPendingEvasion=null;
    this.soldierCancelAttack();
    if(!(this.hp>0)){body.stop();return;}
    var action:String=this.eliteTactics?this.eliteNextAction:"stand";
    if(action=="slide" && this.soldierPendingSlide!==true)action="stand";
    if(action=="line")action="stand"; // Only the dedicated instructor root owns line fire.
    if(action=="slide"){this.soldierPendingSlide=false;this.soldierTacticalStats.slideExits++;}
    var config:Object=eliteMotionConfig.actions[action];
    var first:Number=isFinite(config.entryFrame)?config.entryFrame:config.first,last:Number=config.last;
    var token:Object={};body.soldierToken=token;
    this.soldierAttackOwner={token:token,action:"shoot",elite:true,kind:action,active:true,
        weapon:this.长枪,pistol:this.手枪,sidearm:this.手枪2,version:this.version,target:this.攻击目标,startedAt:this.soldierClock,age:0,shots:0,
        sidearmShots:0,reload:false,reloadSlot:null,burstOpen:false,burstCompleted:false,
        fireDeadline:0,last:last,first:first,logicalFrame:first,strafeSign:this.eliteStrafeSign,
        moveStart:this.eliteMoveDistance,completed:false,shotLimit:0,sidearmShotLimit:0,
        fireEvents:config.fireEvents,eventDone:{},fireGrace:eliteMotionConfig.fireGraceFrames,
        restFrames:this.soldierTacticalConfig.eliteRestFrames,currentWeapon:"",recoilUntil:0,recoilWeapon:""};
    var owner:Object=this.soldierAttackOwner;
    owner.slideMovedZ=0;owner.slideZSign=0;owner.motionFrames=0;owner.retreatMovedX=0;
    owner.reactiveEvasion=action=="retreat" && evasion!=null;
    owner.retreatMovedZ=0;owner.retreatZBlocked=0;
    owner.retreatZSign=evasion!=null?evasion.zSign:0;
    if(action=="retreat" && evasion!=null){
        this.soldierNextEvasionAt=this.soldierClock+this.soldierTacticalConfig.evasionRestFrames;
        this.soldierTacticalStats.evasions++;
        if(this.soldierIsInstructor && this.soldierTacticalPolicy=="adaptive"){
            if(this.soldierStrategy!="mobile")this.soldierTacticalStats.strategyChanges++;
            this.soldierStrategy="mobile";this.soldierStrategyUntil=this.soldierClock+this.soldierTacticalConfig.strategyHoldFrames;
        }
    }
    if(action=="stand")owner.fireEvents=owner.fireEvents.slice(0,this.soldierTacticalConfig.eliteStandShots);
    var entryTarget:MovieClip=_root.gameworld[this.攻击目标];
    owner.retreatLimit=this.soldierTacticalConfig.retreatDistance;
    if(action=="retreat" && evasion!=null && isFinite(entryTarget._x))
        owner.retreatLimit=Math.max(owner.retreatLimit,Math.abs(entryTarget._x-this._x)+this.soldierTacticalConfig.evasionRetreatX);
    owner.advanceSign=entryTarget._x<this._x?-1:entryTarget._x>this._x?1:this.方向=="左"?-1:1;
    owner.faceSign=owner.advanceSign;
    if(action!="stand")this.方向改变(owner.faceSign<0?"左":"右");
    if(!this.eliteTactics && action=="stand")owner.fireEvents=owner.fireEvents.slice(0,3);
    for(var i:Number=0;i<owner.fireEvents.length;i++){
        if(owner.fireEvents[i].weapon=="primary")owner.shotLimit++;
        else owner.sidearmShotLimit++;
    }
    this.eliteActionCounts[action]++;if(action!="stand")this.eliteStrafeSign=-this.eliteStrafeSign;
    body.prepareStandardShotPose=function(frame:String):Void {
        var owner:Object=_parent.soldierAttackOwner;
        if(owner==null || !owner.elite)return;
        owner.recoilUntil=owner.age+2;
        owner.recoilWeapon=frame=="射击2"?"secondary":"primary";
    };
    body.初始化长枪射击函数=_root.主角函数.初始化长枪射击函数;
    body.初始化混合双枪=_root.主角函数.初始化混合双枪;
    body.开始混合手枪换弹=_root.主角函数.开始混合手枪换弹;
    body.混合手枪换弹匣=_root.主角函数.混合手枪换弹匣;
    body.初始化长枪射击函数();
    if(action=="retreat"){
        if(!this.elitePrimaryPistolEnabled()){this.soldierWeaponError="精英主手手枪数据缺失";this.soldierFinishAttack(body);return;}
        body.初始化混合双枪();
    }
    body.腰挂.syncHolsters();
    body.gotoAndStop(first);
    if(body.枪2!=null)body.枪2._visible=owner.kind=="retreat" && this.eliteSidearmEnabled();
    var slot:String=action=="retreat"?"手枪":"长枪";
    if(!(this[slot+"弹匣容量"]>0) || !(this[slot+"属性"].interval>0)){
        this.soldierWeaponError="精英标准武器数据缺失";
        this.soldierFinishAttack(body);return;
    }
    if(this[slot].value.shot>=this[slot+"弹匣容量"]){this.eliteBeginReload(body,slot);return;}
    if(action=="retreat" && this.eliteSidearmEnabled() && this.手枪2.value.shot>=this.手枪2弹匣容量)
        this.eliteBeginReload(body,"手枪2");
};
eliteReloadStart=function(body:MovieClip):Void {
    if(!this.soldierCanAct(body)){body.stop();return;}
    var owner:Object=this.soldierAttackOwner;
    this.动作A=false;this.动作B=false;owner.reload=true;this.soldierReloadCount++;
    delete this.standardShotMoving;
    _root.主角函数.清理射击任务(this,true);
    if(owner.reloadPair){
        // Both hands share one stable gesture and one atomic commit anchor.
        // A lone tube pistol retains its existing per-round path.
        body.dualReloadStartHand="副手";delete body._dualReloadFirstInitStartFrame;
        _root.主角函数.双枪初始化换弹负担(body,331,351,334,365,[351,363]);
        var otherBurden:Number=body.reloadFullBurden;
        body.dualReloadStartHand="主手";delete body._dualReloadFirstInitStartFrame;
        _root.主角函数.双枪初始化换弹负担(body,331,351,334,365,[351,363]);
        body.reloadBurden=body.reloadFullBurden=Math.max(body.reloadFullBurden,otherBurden);
        body.perRoundReload=false;body.reloadCanSelectTube=false;body.reloadHeldMode=false;
    }else if(owner.reloadSlot=="手枪" || owner.reloadSlot=="手枪2"){
        _root.主角函数.双枪初始化换弹负担(body,296,316,299,330,[316,328]);
    }else{
        _root.主角函数.初始化换弹负担(body,261,281,264,295,[281,293]);
    }
    this.soldierBeginSmokeReload(body);
};
eliteReloadGate=function(body:MovieClip):Void {
    if(!this.soldierCanAct(body) || this.soldierAttackOwner.reloadPair)return;
    if(this.soldierAttackOwner.reloadSlot=="手枪" || this.soldierAttackOwner.reloadSlot=="手枪2")_root.主角函数.双枪换弹门禁(body);
    else _root.主角函数.换弹门禁(body);
};
eliteReloadCommit=function(body:MovieClip):Void {
    if(!this.soldierCanAct(body))return;
    var owner:Object=this.soldierAttackOwner;
    if(owner.reloadPair){
        if(owner.reloadMainCommitted || owner.reloadOffCommitted)return;
        owner.reloadMainCommitted=true;owner.reloadOffCommitted=true;
        body.主手换弹匣();body.副手换弹匣();
        return;
    }
    if(this.soldierAttackOwner.reloadSlot=="手枪" || this.soldierAttackOwner.reloadSlot=="手枪2"){
        if(body.perRoundReload===true)return;
        if(body.dualReloadWeaponType!==this.soldierAttackOwner.reloadSlot || typeof body.混合手枪换弹匣!="function"){
            this.soldierWeaponError="Pistol reload context is invalid";
            this.soldierFinishAttack(body);return;
        }
        body.混合手枪换弹匣();return;
    }
    body.换弹匣();
};
eliteReloadEnd=function(body:MovieClip):Void {
    if(!this.soldierCanAct(body)){body.stop();return;}
    var owner:Object=this.soldierAttackOwner;
    _root.主角函数.取消混合换弹.call(body);
    this.soldierCompleteSmokeReload(owner);
    owner.completed=true;owner.completedAt=this.soldierClock;owner.reload=false;owner.reloadSlot=null;owner.reloadPair=false;
    var permit:Object=this.soldierSlidePermit;this.soldierSlidePermit=null;
    if(permit!=null && this.soldierClock<=permit.expiresAt && this.soldierCanSlideExit(permit.target)){
        this.eliteNextAction="slide";this.soldierPendingSlide=true;
        // The windup already ran inside the standard reload transaction.
        // Continue its next pose and let the smoke cover the first push-off.
        var cloud:MovieClip=owner.smokeCloud;
        this.eliteBeginAttack(body);
        if(cloud!=null){cloud.sourceOwner=this.soldierAttackOwner;cloud.coverSlideFrames=6;}
        return;
    }
    this.soldierFinishAttack(body);
};
elitePistolMuzzleMarker=function(body:MovieClip,slot:String):MovieClip {
    var outer:MovieClip=slot=="手枪2"?body.枪2:body.枪;
    if(outer==null || !outer._visible)return null;
    var holder:MovieClip=outer.枪,gun:MovieClip=holder.装扮,marker:MovieClip=gun.枪口位置;
    if(outer._parent!==body || holder._parent!==outer || gun._parent!==holder
        || marker._parent!==gun || gun!==this[slot+"_引用"])return null;
    return marker;
};
eliteSidearmMuzzleMarker=function(body:MovieClip):MovieClip {
    return this.elitePistolMuzzleMarker(body,"手枪2");
};
eliteMove=function(owner:Object,body:MovieClip):Boolean {
    this.standardShotMoving=false;
    if(owner.kind=="stand")return true;
    if(!this.eliteMobility || this.倒地 || this.浮空)return false;
    var target:MovieClip=_root.gameworld[owner.target];
    if(!(target.hp>0) || target.area==null)return false;
    var dx:Number=target._x-this._x,dz:Number=target.Z轴坐标-this.Z轴坐标;
    if(!isFinite(dx) || !isFinite(dz))return false;
    var beforeX:Number=this._x,beforeZ:Number=this.Z轴坐标;
    var frame:Number=owner.logicalFrame,config:Object=this.soldierTacticalConfig;
    var movement:Object=eliteMotionConfig.movement[owner.kind];
    // A backwards-running pose keeps its facing for the whole committed step.
    // Target crossings cannot turn the body while its feet travel the old way.
    this.方向改变(owner.faceSign<0?"左":"右");
    var first:Number=owner.reactiveEvasion?owner.first:movement.firstMovingFrame;
    if(frame<first || frame>movement.lastMovingFrame)return true;
    if(owner.kind=="retreat"){
        // Distance limits selection, not every animation frame. Spread the
        // bounded travel budget over the full run instead of planting its feet.
        var stepX:Number=Math.min(this.跑X速度*movement.speedMultiplier*0.8,
            config.retreatDistance/(movement.lastMovingFrame-first+1),Math.max(0,config.retreatDistance-owner.retreatMovedX));
        this.soldierTacticalMove(owner.faceSign>0?"左":"右",stepX);
        owner.retreatMovedX+=Math.abs(this._x-beforeX);
        if(owner.retreatZSign!=0 && owner.retreatMovedZ<config.retreatZBudget){
            var step:Number=Math.min(this.跑Y速度*config.retreatZSpeed,config.retreatZBudget-owner.retreatMovedZ);
            var movedZ:Number=this.soldierTacticalMove(owner.retreatZSign<0?"上":"下",step);
            owner.retreatMovedZ+=movedZ;
            if(movedZ<0.1 && owner.retreatZBlocked==0){owner.retreatZSign=-owner.retreatZSign;owner.retreatZBlocked++;}
        }
    }else{
        var room:Number=dx*owner.advanceSign-config.slideStopRange;
        if(room<=0)return this.eliteRecoverMovement(owner,body);
        var speed:Number=this.跑X速度*(owner.kind=="run"?movement.runSpeedMultiplier:movement.lowSpeedMultiplier);
        this.soldierTacticalMove(owner.advanceSign>0?"右":"左",Math.min(speed,room));
        if(frame<movement.firstMovingFrame+config.slideTrackFrames && owner.slideMovedZ<config.slideZBudget){
            var direction:Number=dz<0?-1:1;
            if(owner.slideZSign==0)owner.slideZSign=direction;
            if(direction==owner.slideZSign && Math.abs(dz)>this.soldierTuning.laneStopRange){
                var amount:Number=Math.min(this.跑Y速度*config.slideZSpeed,Math.abs(dz)-this.soldierTuning.laneStopRange,config.slideZBudget-owner.slideMovedZ);
                owner.slideMovedZ+=this.soldierTacticalMove(direction<0?"上":"下",amount);
            }
        }
    }
    var travelled:Number=Math.abs(this._x-beforeX)+Math.abs(this.Z轴坐标-beforeZ);
    this.standardShotMoving=travelled>0.1;
    if(travelled>0.1){owner.motionFrames++;this.eliteMoveFrames++;this.eliteMoveDistance+=travelled;return true;}
    // A blocked locomotion pose must leave its moving segment immediately.
    return this.eliteRecoverMovement(owner,body);
};
eliteRecoverMovement=function(owner:Object,body:MovieClip):Boolean {
    if(owner.kind!="slide")return false;
    owner.logicalFrame=229;body.gotoAndStop(229);return true;
};
eliteOpenBurst=function(owner:Object,frame:Number):Void {
    if(owner.burstOpen)return;
    owner.burstOpen=true;
    owner.fireDeadline=this.soldierClock+Math.max(1,owner.last-frame+owner.fireGrace+1);
    this.soldierNextShootAt=this.soldierClock+(owner.last-frame+1)+owner.restFrames;
};
eliteFireWeapon=function(body:MovieClip,weapon:String):Boolean {
    var owner:Object=this.soldierAttackOwner;
    var target:MovieClip=_root.gameworld[this.攻击目标];
    // Lane alignment gates selection, not each shot of an already committed action.
    // Keep its bounded fire events on the shooter's real lane; walking realigns after recovery.
    if(!(target.hp>0))return false;
    if((owner.kind=="slide" || owner.kind=="run") && (target._x-this._x)*owner.advanceSign<=0)return false;
    var slot:String=this.eliteWeaponSlot(weapon);
    if(!this.eliteWeaponReady(slot))return false;
    if(slot=="手枪" && !this.elitePrimaryPistolEnabled())return false;
    if(slot=="手枪2" && !this.eliteSidearmEnabled())return false;
    if(this[slot].value.shot>=this[slot+"弹匣容量"])return false;
    var marker:MovieClip=slot=="长枪"?this.soldierMuzzleMarker(body):this.elitePistolMuzzleMarker(body,slot);
    if(marker==null)return false;
    var interval:Number=this[slot+"属性"].interval;
    var before:Number;
    if(weapon=="primary"){
        if(owner.shots>=owner.shotLimit)return false;
        before=owner.shots;owner.currentWeapon="primary";this.动作A=true;
        body.主手持续射击(this,slot,interval,null,interval);
        this.动作A=false;owner.currentWeapon="";
        return owner.shots>before;
    }
    if(owner.sidearmShots>=owner.sidearmShotLimit)return false;
    before=owner.sidearmShots;owner.currentWeapon="secondary";this.动作B=true;
    body.副手持续射击(this,slot,interval,null,interval);
    this.动作B=false;owner.currentWeapon="";
    return owner.sidearmShots>before;
};
eliteApplyRecoil=function(body:MovieClip):Void {
    var owner:Object=this.soldierAttackOwner;
    if(owner.recoilUntil<=owner.age)return;
    if(owner.recoilWeapon=="secondary" && body.枪2!=null)body.枪2._x-=2;
    else if(owner.recoilWeapon=="primary" && body.枪!=null)body.枪._x-=2;
};
eliteDriveShooting=function(body:MovieClip):Void {
    var owner:Object=this.soldierAttackOwner;
    if(owner.reload){this.soldierMoveSmokeReload(owner,body);_root.主角函数.换弹帧率控制(body);return;}
    if(owner.age==0 && typeof this.eliteCaptureFirstFrame=="function"){
        var firstCapture:Function=this.eliteCaptureFirstFrame;
        delete this.eliteCaptureFirstFrame;
        firstCapture.call(this,body,owner);
    }
    owner.age++;
    if(!this.eliteMove(owner,body)){owner.completed=true;this.soldierFinishAttack(body);return;}
    if(body.枪2!=null)body.枪2._visible=owner.kind=="retreat" && this.eliteSidearmEnabled();
    var frame:Number=owner.logicalFrame;
    for(var i:Number=0;i<owner.fireEvents.length;i++){
        if(owner.eventDone[i]===true)continue;
        var event:Object=owner.fireEvents[i];
        if(frame<event.frame)continue;
        if(frame>event.frame+owner.fireGrace){owner.eventDone[i]=true;continue;}
        if(event.weapon=="secondary" && !this.eliteSidearmEnabled()){owner.eventDone[i]=true;continue;}
        this.eliteOpenBurst(owner,frame);
        var fired:Boolean=this.eliteFireWeapon(body,event.weapon);
        if(fired || frame>=event.frame+owner.fireGrace)owner.eventDone[i]=true;
        var slot:String=this.eliteWeaponSlot(event.weapon);
        if(!fired && this[slot].value.shot>=this[slot+"弹匣容量"]){
            this.eliteBeginReload(body,slot);return;
        }
    }
    if(frame>=owner.last){owner.completed=true;this.soldierFinishAttack(body);return;}
    owner.logicalFrame++;
    body.gotoAndStop(owner.logicalFrame);
    this.eliteApplyRecoil(body);
};
soldierDriveShooting=function(body:MovieClip):Void {
    if(this.soldierAttackOwner.elite)this.eliteDriveShooting(body);
    else this.eliteOriginalDrive(body);
};
长枪射击=function(marker:MovieClip,props:Object):Boolean {
    var body:MovieClip=this.man,owner:Object=this.soldierAttackOwner;
    if(!owner.elite)return this.eliteOriginalFire(marker,props);
    if(!this.soldierCanAct(body) || this.倒地 || this.浮空 || owner.action!="shoot" || owner.reload
        || owner.kind=="retreat" || !this.eliteWeaponReady("长枪")
        || owner.currentWeapon!="primary" || owner.shots>=owner.shotLimit
        || !(this.soldierClock<owner.fireDeadline))return false;
    if(marker!==this.soldierMuzzleMarker(body) || marker==null){this.soldierInvalidMuzzleCount++;return false;}
    var fired:Boolean=_root.主角函数.长枪射击.call(this,marker,props);
    if(fired){this.eliteRecordWeaponShot("长枪");owner.shots++;this.soldierShotCount++;if(owner.shots>=owner.shotLimit)this.动作A=false;}
    return fired;
};
elitePistolShot=function(slot:String,marker:MovieClip,props:Object):Boolean {
    var body:MovieClip=this.man,owner:Object=this.soldierAttackOwner;
    var secondary:Boolean=slot=="手枪2";
    var enabled:Boolean=secondary?this.eliteSidearmEnabled():this.elitePrimaryPistolEnabled();
    if(!owner.elite || !this.soldierCanAct(body) || !enabled || !this.eliteWeaponReady(slot)
        || this.倒地 || this.浮空 || owner.action!="shoot" || owner.kind!="retreat" || owner.reload
        || owner.currentWeapon!=(secondary?"secondary":"primary")
        || (secondary?owner.sidearmShots>=owner.sidearmShotLimit:owner.shots>=owner.shotLimit)
        || !(this.soldierClock<owner.fireDeadline))return false;
    if(marker!==this.elitePistolMuzzleMarker(body,slot) || marker==null){this.soldierInvalidMuzzleCount++;return false;}
    var entry:Function=secondary?_root.主角函数.手枪2射击:_root.主角函数.手枪射击;
    var fired:Boolean=entry.call(this,marker,props);
    if(fired){
        this.eliteRecordWeaponShot(slot);
        if(secondary){owner.sidearmShots++;this.eliteSidearmShotCount++;if(owner.sidearmShots>=owner.sidearmShotLimit)this.动作B=false;}
        else {owner.shots++;this.soldierShotCount++;if(owner.shots>=owner.shotLimit)this.动作A=false;}
    }
    return fired;
};
手枪射击=function(marker:MovieClip,props:Object):Boolean {
    return this.elitePistolShot("手枪",marker,props);
};
手枪2射击=function(marker:MovieClip,props:Object):Boolean {
    return this.elitePistolShot("手枪2",marker,props);
};
