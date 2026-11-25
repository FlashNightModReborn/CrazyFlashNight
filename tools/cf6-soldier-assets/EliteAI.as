// Elite-only motion and mixed-weapon adapter. Ordinary soldiers keep their own controller.
soldierIsElite=true;
eliteActionCounts={stand:0,retreat:0,run:0,slide:0};eliteMoveFrames=0;eliteMoveDistance=0;
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
    var next:String=this.soldierIsInstructor===true?(this.soldierPhase==1?"重盾教官":"战术教官"):(this.soldierPhase==1?"攻坚盾卫":"机动特勤");
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
    if(!_root.暂停 && ((owner.elite && owner.kind=="stand") || owner.standUnified===true)
        && !owner.reload && owner.age>=12 && this.soldierCanAct(this.man)){
        var target:MovieClip=_root.gameworld[this.攻击目标];
        if(this.soldierTryEvasion(Math.abs(target._x-this._x),Math.abs(target.Z轴坐标-this.Z轴坐标))){
            // Preserve weapon cadence/ammunition; only this stationary action yields.
            this.soldierFinishAttack(this.man);return;
        }
    }
    if((owner.elite || owner.charge) && this.硬直中 && !this.倒地 && !this.浮空 && this.soldierCanAct(this.man)){
        this.soldierClock++;
        if(this.soldierTryShieldGuard())return;
        this.soldierDriveShooting(this.man);return;
    }
    this.eliteOriginalTick();
    // A movement-only wall escape may leave light hitstop, just like the
    // existing committed retreat; genuine hit/down/airborne states still win.
    if(!_root.暂停 && this.soldierAttackOwner==null && this.硬直中
        && this.soldierPendingEvasion.noFire===true && !this.倒地 && !this.浮空
        && (this.状态=="长枪站立" || this.状态=="长枪行走" || this.状态=="长枪跑")){
        var escapeTarget:MovieClip=_root.gameworld[this.攻击目标];
        if(this.soldierTryEvasion(Math.abs(escapeTarget._x-this._x),Math.abs(escapeTarget.Z轴坐标-this.Z轴坐标))){
            this.soldierClearMovement();this.方向改变(escapeTarget._x<this._x?"左":"右");
            this.状态改变("长枪攻击");
        }
    }
};
soldierCancelAttack=function():Void {
    var previous:Object=this.soldierAttackOwner;
    this.soldierClearRecoil(previous);
    if(typeof this.soldierReleaseChargeObserver=="function")this.soldierReleaseChargeObserver();
    if(previous.charge && this.特种兵战术诊断===true && typeof _root.服务器.发布服务器消息=="function")
        _root.服务器.发布服务器消息("[CF6-CHARGE-ACTION] unit="+this._name+" age="+previous.age
            +" moved="+previous.distance+" movedZ="+previous.chargeMovedZ+" turns="+previous.turns
            +" shots="+previous.shots+" contact="+(previous.contactCommitted?1:0)+" hp="+this.hp);
    if(previous.elite && previous.reload && this.man._currentframe>=previous.reloadEndFrame)previous.completed=true;
    if(previous.elite || previous.standUnified){
        if(previous.completed)this.eliteCompletedActions++;else this.eliteInterruptedActions++;
        if(this.特种兵精英诊断===true && typeof _root.服务器.发布服务器消息=="function"){
            _root.服务器.发布服务器消息("[CF6-ELITE-ACTION] unit="+this._name+" kind="+(previous.standUnified?"stand":previous.kind)
                +" completed="+(previous.completed?1:0)+" shots="+previous.shots+"/"+previous.shotLimit
                +" sidearm="+previous.sidearmShots+"/"+previous.sidearmShotLimit
                +" moved="+Math.round(this.eliteMoveDistance-(previous.moveStart || 0))+" age="+previous.age
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
eliteMaintainPistols=function():Void {
    if(this.手枪!=null && this.手枪.value!=null && this.手枪弹匣容量>0 && this.手枪.value.shot>=this.手枪弹匣容量)
        this.手枪.value.shot=0;
    if(this.手枪2!=null && this.手枪2.value!=null && this.手枪2弹匣容量>0 && this.手枪2.value.shot>=this.手枪2弹匣容量)
        this.手枪2.value.shot=0;
};
eliteBeginReload=function(body:MovieClip,slot:String):Void {
    var owner:Object=this.soldierAttackOwner;
    if(owner==null || owner.reload)return;
    // Pistol reload is removed per Alter art spec; silently maintain pistol magazines.
    if(slot=="手枪" || slot=="手枪2"){
        if(this[slot]!=null && this[slot].value!=null)this[slot].value.shot=0;
        return;
    }
    this.soldierClearRecoil(owner);
    owner.kind="reload";owner.reload=true;owner.reloadSlot="长枪";
    owner.reloadEndFrame=eliteMotionConfig.reloadEndFrame;
    body.腰挂.syncHolsters();
    this.动作A=false;this.动作B=false;
    _root.主角函数.清理射击任务(this,true);
    body.开始换弹();
};
eliteBeginAttack=function(body:MovieClip):Void {
    var evasion:Object=this.soldierPendingEvasion;this.soldierPendingEvasion=null;
    this.soldierCancelAttack();
    if(!(this.hp>0)){body.stop();return;}
    var action:String=this.eliteTactics && this.eliteMobility?this.eliteNextAction:"run";
    if(action!="retreat" && action!="run" && action!="slide")action="run";
    if(action=="slide"){
        this.soldierSmokeNextAt=this.soldierClock+this.soldierTacticalConfig.smokeRestFrames;
        this.soldierTacticalStats.slideExits++;
    }
    var config:Object=eliteMotionConfig.actions[action];
    var first:Number=config.first,last:Number=config.last;
    var token:Object={};body.soldierToken=token;
    this.soldierAttackOwner={token:token,action:"shoot",elite:true,kind:action,active:true,
        weapon:this.长枪,pistol:this.手枪,sidearm:this.手枪2,version:this.version,target:this.攻击目标,startedAt:this.soldierClock,age:0,shots:0,
        sidearmShots:0,reload:false,reloadSlot:null,burstOpen:false,burstCompleted:false,
        fireDeadline:0,last:last,first:first,logicalFrame:first,strafeSign:this.eliteStrafeSign,
        moveStart:this.eliteMoveDistance,completed:false,shotLimit:0,sidearmShotLimit:0,
        fireEvents:config.fireEvents,eventDone:{},fireGrace:eliteMotionConfig.fireGraceFrames,
        restFrames:this.soldierTacticalConfig.eliteRestFrames,currentWeapon:""};
    var owner:Object=this.soldierAttackOwner;
    owner.slideMovedZ=0;owner.slideZSign=0;owner.motionFrames=0;owner.retreatMovedX=0;
    owner.reactiveEvasion=action=="retreat" && evasion!=null;
    owner.retreatMovedZ=0;owner.retreatZBlocked=0;owner.retreatXBlocked=false;
    owner.retreatZSign=evasion!=null?evasion.zSign:0;
    if(action=="retreat" && evasion!=null){
        // A failed attempt has a short retry delay. Full cooldown requires real travel.
        this.soldierNextEvasionAttemptAt=this.soldierClock+this.soldierTacticalConfig.evasionRetryFrames;
    }
    owner.wallEscape=action=="retreat" && evasion!=null && evasion.noFire===true;
    if(owner.wallEscape)owner.fireEvents=[];
    var entryTarget:MovieClip=_root.gameworld[this.攻击目标];
    var entryDistance:Number=Math.abs(entryTarget._x-this._x);
    if(!isFinite(entryDistance))entryDistance=300;
    owner.retreatLimit=Math.min(this.soldierTacticalConfig.retreatDistance,
        Math.max(this.soldierTacticalConfig.evasionRetreatX,this.soldierTacticalConfig.retreatKeepRange-entryDistance));
    owner.advanceSign=entryTarget._x<this._x?-1:entryTarget._x>this._x?1:this.方向=="左"?-1:1;
    owner.faceSign=owner.advanceSign;
    owner.slideMovedX=0;owner.slideStalledFrames=0;
    if(action=="slide"){
        owner.slideTravelBudget=Math.min(this.soldierTacticalConfig.slideMaxTravel,
            Math.max(180,entryDistance+this.soldierTacticalConfig.slidePassDistance));
        // Weighted travel budget aligned with Alter FX: sprint (f96-132, 37*0.75),
        // speed-line low slide (f133-152, 20*1.50), progressive crouch brake (f153-165, 3*0.85+3*0.45+3*0.25+4*0.15).
        owner.slideBaseStep=owner.slideTravelBudget/63;
    }
    this.方向改变(owner.faceSign<0?"左":"右");
    for(var i:Number=0;i<owner.fireEvents.length;i++){
        if(owner.fireEvents[i].weapon=="primary")owner.shotLimit++;
        else owner.sidearmShotLimit++;
    }
    this.eliteActionCounts[action]=(this.eliteActionCounts[action] || 0)+1;
    if(this.soldierIsInstructor===true){this.soldierMobileVolleys=(this.soldierMobileVolleys||0)+1;this.soldierLineVolleys=0;}
    this.eliteStrafeSign=-this.eliteStrafeSign;
    body.prepareStandardShotPose=function(frame:String):Void {
        this._parent.soldierArmRecoil(this,frame=="射击2",owner.age,owner);
    };
    body.初始化长枪射击函数=_root.主角函数.初始化长枪射击函数;
    body.初始化混合双枪=_root.主角函数.初始化混合双枪;
    body.初始化长枪射击函数();
    if(action=="retreat"){
        if(!this.elitePrimaryPistolEnabled()){this.soldierWeaponError="精英主手手枪数据缺失";this.soldierFinishAttack(body);return;}
        this.eliteMaintainPistols();
        body.初始化混合双枪();
    }
    body.gotoAndStop(first);
    body.腰挂.syncHolsters();
    if(body.枪2!=null)body.枪2._visible=owner.kind=="retreat" && this.eliteSidearmEnabled();
    var slot:String=action=="retreat"?"手枪":"长枪";
    if(!(this[slot+"弹匣容量"]>0) || !(this[slot+"属性"].interval>0)){
        this.soldierWeaponError="精英标准武器数据缺失";
        this.soldierFinishAttack(body);return;
    }
    if(slot=="长枪" && this.长枪.value.shot>=this.长枪弹匣容量){
        if(action=="slide")owner.deferredReloadSlot="长枪";
        else {this.eliteBeginReload(body,"长枪");return;}
    }
};
eliteReloadStart=function(body:MovieClip):Void {
    if(!this.soldierCanAct(body)){body.stop();return;}
    var owner:Object=this.soldierAttackOwner;
    this.soldierClearRecoil(owner);
    this.动作A=false;this.动作B=false;owner.reload=true;this.soldierReloadCount++;
    delete this.standardShotMoving;
    _root.主角函数.清理射击任务(this,true);
    _root.主角函数.初始化换弹负担(body,182,202,185,216,[202,214]);
};
eliteReloadGate=function(body:MovieClip):Void {
    if(!this.soldierCanAct(body))return;
    _root.主角函数.换弹门禁(body);
};
eliteReloadCommit=function(body:MovieClip):Void {
    if(!this.soldierCanAct(body))return;
    body.换弹匣();
};
eliteReloadEnd=function(body:MovieClip):Void {
    if(!this.soldierCanAct(body)){body.stop();return;}
    var owner:Object=this.soldierAttackOwner;
    body.结束换弹();
    owner.completed=true;owner.completedAt=this.soldierClock;owner.reload=false;owner.reloadSlot=null;
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
eliteQueueSlideEscape=function(owner:Object,reason:String):Void {
    if(owner.slideExitQueued)return;
    owner.slideExitQueued=true;
    var target:MovieClip=_root.gameworld[owner.target];
    if(!(target.hp>0))return;
    this.soldierPendingEvasion={target:target,until:this.soldierClock+24,
        zSign:this.soldierEvasionZSign(),noFire:reason=="slide_blocked",reason:reason};
    if(reason=="slide_blocked")this.soldierTacticalStats.slideBlocks++;
    else this.soldierTacticalStats.slideStalls++;
};
eliteSlideAdvance=function(owner:Object):Void {
    var frame:Number=owner.logicalFrame;
    var remW:Number=Math.max(0,133-frame)*0.75
        +Math.max(0,153-Math.max(133,frame))*1.5
        +Math.max(0,156-Math.max(153,frame))*0.85
        +Math.max(0,159-Math.max(156,frame))*0.45
        +Math.max(0,162-Math.max(159,frame))*0.25
        +Math.max(0,166-Math.max(162,frame))*0.15;
    var weight:Number=frame<133?0.75:frame<=152?1.5:frame<=155?0.85:frame<=158?0.45:frame<=161?0.25:0.15;
    var budgetLeft:Number=Math.max(0,owner.slideTravelBudget-owner.slideMovedX);
    var maxStep:Number=this.跑X速度*this.soldierTacticalConfig.slideSpeedLimit;
    var planned:Number=Math.min(maxStep,remW>0?budgetLeft*weight/remW:budgetLeft);
    var remaining:Number=Math.min(planned,budgetLeft);
    while(remaining>0.01){
        var step:Number=Math.min(6,remaining),before:Number=this._x;
        this.soldierTacticalMove(owner.advanceSign>0?"右":"左",step);
        var moved:Number=(this._x-before)*owner.advanceSign;
        if(moved>0)owner.slideMovedX+=moved;
        remaining-=step;
        if(moved<step-0.1){owner.slideBlocked=true;break;}
    }
};
eliteMove=function(owner:Object,body:MovieClip):Boolean {
    owner.stopForBlockedRetreat=false;
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
    // A backwards-running or sliding pose keeps its entry facing until recovery.
    this.方向改变(owner.faceSign<0?"左":"右");
    var first:Number=movement.firstMovingFrame;
    if(owner.kind=="slide" && frame>movement.lastMovingFrame){
        // Play authored stand-up recovery (f166-180) in place; face target as recovery settles.
        if(frame>=176 && target._x!=this._x){
            owner.faceSign=target._x<this._x?-1:1;
            this.方向改变(owner.faceSign<0?"左":"右");
        }
        return true;
    }
    if(frame<first || frame>movement.lastMovingFrame)return true;
    if(owner.kind=="slide"){
        var worldFrame:Number=_root.帧计时器.当前帧数;
        if(owner.slideWorldFrame!=undefined && worldFrame>owner.slideWorldFrame){
            var netForward:Number=(this._x-owner.slidePreviousX)*owner.advanceSign;
            owner.slideStalledFrames=netForward>0.1?0:owner.slideStalledFrames+1;
            if(owner.slideStalledFrames>=2){
                owner.slideStalled=true;this.eliteQueueSlideEscape(owner,"slide_stalled");return false;
            }
        }
        owner.slideWorldFrame=worldFrame;owner.slidePreviousX=this._x;
    }
    if(owner.kind=="retreat"){
        // Spread the bounded travel budget over the authored backward-running frames (f17-67).
        var moveSpan:Number=movement.lastMovingFrame-first+1;
        var stepX:Number=owner.retreatXBlocked?0:Math.min(
            Math.min(this.跑X速度*movement.speedMultiplier*0.8,owner.retreatLimit/moveSpan),
            Math.max(0,owner.retreatLimit-owner.retreatMovedX));
        if(stepX>0){
            this.soldierTacticalMove(owner.faceSign>0?"左":"右",stepX);
            var movedX:Number=Math.abs(this._x-beforeX);
            owner.retreatMovedX+=movedX;
            if(stepX>0.1 && movedX<0.1)owner.retreatXBlocked=true;
        }
        if(owner.retreatXBlocked && owner.retreatZSign==0)owner.retreatZSign=this.soldierEvasionZSign();
        if(owner.retreatZSign!=0 && owner.retreatMovedZ<config.retreatZBudget){
            var zRemain:Number=config.retreatZBudget-owner.retreatMovedZ;
            var zMax:Number=this.跑Y速度*config.retreatZSpeed;
            var zBase:Number=Math.min(zMax,zRemain);
            var step:Number=owner.retreatXBlocked
                ?Math.min(zBase,Math.max(0.2,zRemain/Math.max(1,movement.lastMovingFrame-frame+1)))
                :zBase;
            var movedZ:Number=this.soldierTacticalMove(owner.retreatZSign<0?"上":"下",step);
            if(movedZ<0.1 && owner.retreatZBlocked==0){
                owner.retreatZSign=-owner.retreatZSign;owner.retreatZBlocked++;
                movedZ=this.soldierTacticalMove(owner.retreatZSign<0?"上":"下",step);
            }
            owner.retreatMovedZ+=movedZ;
        }
    }else{
        if(owner.kind=="slide"){
            this.eliteSlideAdvance(owner);
            if(owner.slideBlocked){this.eliteQueueSlideEscape(owner,"slide_blocked");return false;}
        }else{
            var room:Number=dx*owner.advanceSign-config.runStopRange;
            if(room<=0)return this.eliteRecoverMovement(owner,body);
            this.soldierTacticalMove(owner.advanceSign>0?"右":"左",Math.min(this.跑X速度*movement.runSpeedMultiplier,room));
        }
        if(frame<movement.firstMovingFrame+config.slideTrackFrames && owner.slideMovedZ<config.slideZBudget){
            var direction:Number=dz<0?-1:1;
            if(owner.slideZSign==0)owner.slideZSign=direction;
            if(direction==owner.slideZSign && Math.abs(dz)>this.soldierTuning.laneStopRange){
                var amount:Number=Math.min(this.跑Y速度*config.slideZSpeed,Math.min(Math.abs(dz)-this.soldierTuning.laneStopRange,config.slideZBudget-owner.slideMovedZ));
                owner.slideMovedZ+=this.soldierTacticalMove(direction<0?"上":"下",amount);
            }
        }
    }
    var travelled:Number=Math.abs(this._x-beforeX)+Math.abs(this.Z轴坐标-beforeZ);
    this.standardShotMoving=travelled>0.1;
    if(travelled>0.1){
        owner.motionFrames++;this.eliteMoveFrames++;this.eliteMoveDistance+=travelled;
        if(owner.reactiveEvasion && !owner.evasionCommitted){
            owner.evasionCommitted=true;
            if(owner.wallEscape)this.soldierTacticalStats.wallEscapes++;else this.soldierTacticalStats.evasions++;
            this.soldierNextEvasionAt=Math.max(this.soldierNextEvasionAt,this.soldierClock+config.evasionRestFrames);
            if(this.soldierIsInstructor && this.soldierTacticalPolicy=="adaptive"){
                if(this.soldierStrategy!="mobile")this.soldierTacticalStats.strategyChanges++;
                this.soldierStrategy="mobile";this.soldierStrategyUntil=this.soldierClock+config.strategyHoldFrames;
            }
        }
        return true;
    }
    if(owner.kind=="slide" && owner.slideMovedX>=owner.slideTravelBudget-0.1)return true;
    if(owner.kind=="retreat" && owner.retreatMovedX>=owner.retreatLimit-0.1)return true;
    // Only this validated, motionless retreat may settle due shots before finishing.
    owner.stopForBlockedRetreat=owner.kind=="retreat" && owner.retreatXBlocked===true;
    // A blocked locomotion pose must leave its moving segment immediately.
    return this.eliteRecoverMovement(owner,body);
};
eliteRecoverMovement=function(owner:Object,body:MovieClip):Boolean {
    if(owner.kind=="run"){
        // Stopped feet enter the standing shoulder-aim handoff frame (f181).
        // Retain this attack's ammunition and remaining ceiling; never coast through a running loop.
        var framesLeft:Number=owner.last-owner.logicalFrame+1;
        if(!owner.burstOpen){
            owner.fireDeadline=this.soldierClock+framesLeft+owner.fireGrace;
            this.soldierNextShootAt=Math.max(this.soldierNextShootAt,this.soldierClock+framesLeft+owner.restFrames);
            owner.burstOpen=true;
        }
        this.soldierClearRecoil(owner);
        var standFrame:Number=eliteMotionConfig.handoffFrame;
        owner.kind="stand";owner.runHandoff=true;owner.logicalFrame=standFrame;owner.eventDone={};owner.fireEvents=[];
        var target:MovieClip=_root.gameworld[owner.target];
        if(target._x!=this._x){
            owner.faceSign=target._x<this._x?-1:1;
            this.方向改变(owner.faceSign<0?"左":"右");
        }
        var remaining:Number=Math.max(0,owner.shotLimit-owner.shots);
        owner.last=standFrame+Math.max(1,framesLeft)-1;
        for(var i:Number=0;i<remaining && standFrame+2+i*4<=owner.last;i++)
            owner.fireEvents.push({frame:standFrame+2+i*4,weapon:"primary"});
        body.gotoAndStop(standFrame);return true;
    }
    return false;
};
eliteOpenBurst=function(owner:Object,frame:Number):Void {
    if(owner.burstOpen)return;
    owner.burstOpen=true;
    owner.fireDeadline=this.soldierClock+Math.max(1,owner.last-frame+owner.fireGrace+1);
    this.soldierNextShootAt=this.soldierClock+(owner.last-frame+1)+owner.restFrames;
};
eliteOwnsBody=function(owner:Object,body:MovieClip):Boolean {
    return owner===this.soldierAttackOwner && body===this.man && body.soldierToken===owner.token && owner.version===this.version;
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
    if((slot=="手枪" || slot=="手枪2") && this[slot].value.shot>=this[slot+"弹匣容量"])this[slot].value.shot=0;
    if(this[slot].value.shot>=this[slot+"弹匣容量"])return false;
    var marker:MovieClip=slot=="长枪"?this.soldierMuzzleMarker(body):this.elitePistolMuzzleMarker(body,slot);
    if(marker==null)return false;
    var interval:Number=this[slot+"属性"].interval;
    var before:Number;
    if(weapon=="primary"){
        if(owner.shots>=owner.shotLimit)return false;
        before=owner.shots;owner.currentWeapon="primary";this.动作A=true;
        body.主手持续射击(this,slot,interval,null,interval);
        if(this.eliteOwnsBody(owner,body))this.动作A=false;
        owner.currentWeapon="";
        return owner.shots>before;
    }
    if(owner.sidearmShots>=owner.sidearmShotLimit)return false;
    before=owner.sidearmShots;owner.currentWeapon="secondary";this.动作B=true;
    body.副手持续射击(this,slot,interval,null,interval);
    if(this.eliteOwnsBody(owner,body))this.动作B=false;
    owner.currentWeapon="";
    return owner.sidearmShots>before;
};
eliteDisplayFrame=function(owner:Object):Number {
    if(owner.runHandoff)return eliteMotionConfig.handoffFrame;
    if(owner.kind=="run" && owner.logicalFrame>124)return 100+((owner.logicalFrame-125)%25);
    return owner.logicalFrame;
};
eliteDriveShooting=function(body:MovieClip):Void {
    var owner:Object=this.soldierAttackOwner;
    if(owner.reload){_root.主角函数.换弹帧率控制(body);return;}
    if(owner.age==0 && typeof this.eliteCaptureFirstFrame=="function"){
        var firstCapture:Function=this.eliteCaptureFirstFrame;
        delete this.eliteCaptureFirstFrame;
        firstCapture.call(this,body,owner);
        if(!this.eliteOwnsBody(owner,body))return;
    }
    owner.age++;
    var moved:Boolean=this.eliteMove(owner,body);
    if(!this.eliteOwnsBody(owner,body))return;
    var finishAtWall:Boolean=!moved && owner.stopForBlockedRetreat && !owner.wallEscape;
    if(!moved && !finishAtWall){
        owner.completed=true;this.soldierFinishAttack(body);return;
    }
    if(!this.soldierCanAct(body) || this.倒地 || this.浮空)return;
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
        // The synchronous pre-fire dispatch can cancel or replace this owner.
        if(!this.eliteOwnsBody(owner,body))return;
        if(fired || frame>=event.frame+owner.fireGrace)owner.eventDone[i]=true;
        var slot:String=this.eliteWeaponSlot(event.weapon);
        if(!fired && slot=="长枪" && this.长枪.value.shot>=this.长枪弹匣容量){
            if(owner.kind=="slide" || owner.runHandoff){
                if(owner.deferredReloadSlot==null)owner.deferredReloadSlot="长枪";
                owner.eventDone[i]=true;
            }else{this.eliteBeginReload(body,"长枪");return;}
        }
    }
    if(finishAtWall){owner.completed=true;this.soldierFinishAttack(body);return;}
    if(frame>=owner.last){
        if(owner.deferredReloadSlot=="长枪"){this.eliteBeginReload(body,"长枪");return;}
        owner.completed=true;this.soldierFinishAttack(body);return;
    }
    owner.logicalFrame++;
    this.soldierResetRecoilPose(owner);
    body.gotoAndStop(this.eliteDisplayFrame(owner));
    body.腰挂.syncHolsters();
    if(body.枪2!=null)body.枪2._visible=owner.kind=="retreat" && this.eliteSidearmEnabled();
    this.soldierApplyRecoil(body,owner.age,owner);
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
    // The sustained-fire dispatcher can retire this target before the projectile commit.
    var target:MovieClip=_root.gameworld[owner.target];
    if(!(target.hp>0) || target.area==null)return false;
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
