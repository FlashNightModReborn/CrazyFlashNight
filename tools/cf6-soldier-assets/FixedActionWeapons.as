// Real ShootCore / ReloadManager adapters; no synthetic magazine refills.
cf6FixedBit=function(slot:String):Number {
    return slot=="长枪"?1:slot=="手枪"?2:slot=="手枪2"?4:slot=="长枪副武器"?8:0;
};
cf6FixedUnits=function(slot:String,props:Object):Number {
    var split:Number=Math.ceil(Number(props.霰弹值));
    if(slot=="长枪" && typeof this.cf6G1111FixedMode=="boolean")return this.cf6G1111FixedMode?6:1;
    if(slot=="长枪" && isFinite(this.cf6Profile.budget.primaryFinalDamageUnitsPerAction)){
        var effectUnits:Number=this.cf6Profile.budget.primaryFinalDamageUnitsPerAction/this.cf6Profile.budget.primaryTriggerLimit;
        return Math.max(split,effectUnits);
    }
    if(slot=="长枪副武器")return Math.max(split,this.cf6Profile.budget.subweaponFinalDamageUnitsPerAction);
    return split;
};
cf6FixedSlotReady=function(slot:String):Boolean {
    var cadence:Object=this.cf6Cadence[slot];
    if(cadence==null)return true;
    return cadence.weapon===this[slot] && this.cf6Observation.frame>=cadence.frame && getTimer()>=cadence.time;
};
cf6FixedPrepareShot=function(slot:String,props:Object):Boolean {
    var bit:Number=this.cf6FixedBit(slot);
    var suppression:Object=this.cf6Profile.program.suppression;
    if(slot=="长枪" && suppression!=null && this.长枪.name!==suppression.weaponName)return false;
    if(this.cf6FixedError!=undefined || bit==0 || bit!=this.cf6CurrentFireBit
        || !this.cf6FixedCanAct(this.man) || !this.cf6FixedSlotReady(slot)
        || this.dispatcher==null || this.dispatcher.isDestroyed())return false;
    var owner:Object=this.soldierAttackOwner;
    if(owner.reload || this.硬直中 || !owner.fixed)return false;
    this.cf6ActionApi.refreshFire(this.cf6ActionRecord,_root.gameworld[this.攻击目标],this.cf6Observation,true);
    this.cf6Observation.modeReady=this.cf6FixedModeReady(owner.mode);this.cf6Observation.readyMode=owner.mode;
    if(typeof this.cf6G1111FixedMode=="boolean" && slot=="长枪"){
        if(!this.cf6Observation.fixedModeValid || this.铁枪之锋许可===true)return false;
        var ref:Object=this.__cf6G1111;
        if(ref==null || ref.weaponValue!==this.长枪.value || ref.cf6Version!==this.version
            || ref.cf6Weapon!==this.长枪 || ref.isRocketMode!==this.cf6G1111FixedMode)return false;
    }
    return this.cf6RuleCanCommit(this.cf6ActionState,this.cf6Profile,this.cf6Observation,bit,this.cf6FixedUnits(slot,props));
};
cf6FixedArmShot=function(slot:String,props:Object):Boolean {
    if(!this.cf6FixedPrepareShot(slot,props))return false;
    this.cf6PendingShot={slot:slot,body:this.man,owner:this.soldierAttackOwner,weapon:this[slot],
        cycle:this.cf6ActionState.cycle,stage:this.cf6ActionState.index,frame:this.cf6Observation.frame,
        subReady:this.cf6Observation.subReady,shotBefore:this[slot].value.shot};
    return true;
};
cf6FixedFinalizeShot=function(slot:String,props:Object):Boolean {
    var pending:Object=this.cf6PendingShot;this.cf6PendingShot=null;
    if(pending==null || pending.slot!=slot || pending.body!==this.man || pending.owner!==this.soldierAttackOwner
        || pending.weapon!==this[slot] || pending.cycle!==this.cf6ActionState.cycle
        || pending.stage!==this.cf6ActionState.index || !this.cf6FixedCanAct(this.man))return false;
    if(this[slot].value.shot!==pending.shotBefore+1 || !isFinite(props.shootX)
        || !isFinite(props.shootY) || !isFinite(props.shootZ)){
        this.cf6ActionApi.error(this.cf6ActionRecord,"missing native ammunition/muzzle commit");return false;
    }
    this.cf6ActionApi.refreshFire(this.cf6ActionRecord,_root.gameworld[this.攻击目标],this.cf6Observation,true);
    this.cf6Observation.modeReady=this.cf6FixedModeReady(this.soldierAttackOwner.mode);
    this.cf6Observation.readyMode=this.soldierAttackOwner.mode;
    // The pre-commit receipt proves the just-consumed last round existed.
    if(slot=="长枪副武器")this.cf6Observation.subReady=pending.subReady;
    var s:Object=this.cf6ActionState,o:Object=this.cf6Observation,bit:Number=this.cf6FixedBit(slot);
    if(typeof this.cf6G1111FixedMode=="boolean" && slot=="长枪"){
        props.子弹种类=this.cf6G1111FixedMode?"横向拖尾追踪联弹-普通无壳子弹":"铁枪磁轨弹";
        props.伤害类型=this.cf6G1111FixedMode?"破击":"魔法";
        props.魔法伤害属性=this.cf6G1111FixedMode?"首领":"能";
        props.霰弹值=this.cf6G1111FixedMode?6:1;
    }
    var units:Number=this.cf6FixedUnits(slot,props);
    var ceiling:Number=bit==1?this.cf6Profile.budget.primarySplit:bit==8?this.cf6Profile.budget.subweaponFinalDamageUnitsPerAction:
        Math.ceil(this.cf6Profile.budget.sidearmProjectilesPerAction/(2*this.cf6Profile.budget.sidearmSynchronizedTriggerLimit));
    if(bit==1 && isFinite(this.cf6Profile.budget.primaryFinalDamageUnitsPerAction))
        ceiling=this.cf6Profile.budget.primaryFinalDamageUnitsPerAction/this.cf6Profile.budget.primaryTriggerLimit;
    if(units>ceiling || pending.frame!==o.frame)return false;
    if(!this.cf6RuleCanCommit(s,this.cf6Profile,o,bit,units))return false;
    // Apply after every equipment processShot listener. The visible line is the
    // real ground lane, not a fresh auto-target projection after the lock.
    props.固定枪口方向=true;props.速度X=s.aimSign*props.子弹速度;props.速度Y=0;props.ZY比例=undefined;
    props.角度偏移=0;props.shootZ=this.Z轴坐标;
    if(typeof this.cf6G1111FixedMode=="boolean" && slot=="长枪")props.子弹散射度=0;
    var group:Object=this.cf6Groups.begin(this.cf6ActionRecord,s.cycle);
    if(group==null)return false;
    props.cf6DamageGroup=group;
    props.cf6FixedFlight=this.cf6G1111FixedMode===true && slot=="长枪";
    if(props.cf6FixedFlight){
        props.cf6BoundTarget=_root.gameworld[this.攻击目标];
        props.cf6BoundTargetVersion=o.targetVersion;props.cf6BoundTargetKey=o.targetKey;
    }else{
        delete props.cf6BoundTarget;delete props.cf6BoundTargetVersion;delete props.cf6BoundTargetKey;
    }
    this.cf6RuleCommitted(s,this.cf6Profile,o,bit,units);
    return true;
};
cf6FixedShotDispatched=function(slot:String,props:Object):Void {
    this.cf6Groups.seal(props.cf6DamageGroup);
    delete props.cf6DamageGroup;
    var cadence:Object=this.cf6Cadence[slot];
    if(cadence==null){cadence={};this.cf6Cadence[slot]=cadence;}
    var interval:Number=Number(this[slot+"属性"].interval);
    if(!(interval>0))interval=1000;
    if(slot=="长枪" && this.cf6FirstPrimaryFrame==undefined){
        this.cf6FirstPrimaryFrame=this.cf6Observation.frame;
        this.cf6FirstPrimaryDistance=this.cf6Observation.distance;
        this.cf6FirstPrimaryX=this._x;this.cf6FirstTargetX=this.cf6Observation.targetX;
    }
    cadence.weapon=this[slot];cadence.frame=this.cf6Observation.frame+Math.max(1,Math.ceil(interval*30/1000));
    cadence.time=getTimer()+interval;
    cadence.bulletType=props.子弹种类;cadence.split=props.霰弹值;cadence.lastShotFrame=this.cf6Observation.frame;
    if(slot=="长枪" && typeof this.cf6G1111FixedMode=="boolean")this.__cf6G1111.fireRequest=true;
    this.soldierShotCount++;this.soldierAttackOwner.shots++;
    if(slot=="手枪2")this.eliteSidearmShotCount++;
};
cf6FixedGun=function(slot:String,marker:MovieClip,props:Object):Boolean {
    var expected:MovieClip=slot=="长枪"?this.soldierMuzzleMarker(this.man):this.elitePistolMuzzleMarker(this.man,slot);
    if(marker==null || marker!==expected || !this.cf6FixedPrepareShot(slot,props))return false;
    var entry:Function=slot=="长枪"?_root.主角函数.长枪射击:slot=="手枪"?_root.主角函数.手枪射击:_root.主角函数.手枪2射击;
    return entry.call(this,marker,props);
};
cf6FixedLongFire=function(marker:MovieClip,props:Object):Boolean {return this.cf6FixedGun("长枪",marker,props);};
cf6FixedPistolFire=function(marker:MovieClip,props:Object):Boolean {return this.cf6FixedGun("手枪",marker,props);};
cf6FixedOffFire=function(marker:MovieClip,props:Object):Boolean {return this.cf6FixedGun("手枪2",marker,props);};
cf6FixedFireSlot=function(slot:String,bit:Number):Void {
    if(!this.cf6FixedSlotReady(slot))return;
    if(this[slot].value.shot>=this[slot+"弹匣容量"]){
        this.cf6FixedCancel("empty_magazine");this.cf6ReloadRequested=slot;return;
    }
    this.cf6CurrentFireBit=bit;
    var body:MovieClip=this.man,interval:Number=this[slot+"属性"].interval;
    this.方向改变(this.cf6ActionState.aimSign<0?"左":"右");
    if(bit==4){this.动作B=true;body.副手持续射击(this,slot,interval,null,interval);this.动作B=false;}
    else {this.动作A=true;body.主手持续射击(this,slot,interval,null,interval);this.动作A=false;}
    this.cf6CurrentFireBit=0;
};
cf6FixedFire=function(mask:Number):Void {
    if(mask&1)this.cf6FixedFireSlot("长枪",1);
    if(mask&2)this.cf6FixedFireSlot("手枪",2);
    if(mask&4)this.cf6FixedFireSlot("手枪2",4);
    if(mask&8)this.cf6FixedFireSub();
    if(mask&16)this.cf6FixedThrow(this.man);
};
cf6FixedFireSub=function():Void {
    var body:MovieClip=this.man,owner:Object=this.soldierAttackOwner;
    if(!this.cf6FixedModeReady("sub") || !this.cf6FixedSlotReady("长枪副武器"))return;
    var api:Object=_global.org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
    if(!(api.getLoadedCount(this)>0))return;
    var context:Object=owner.subContext;
    if(context==null){
        context=api.buildShootContext(this);context.man=body;context.refreshManEachTick=false;
        context.fireMethodName="soldierSubweaponFire";owner.subContext=context;
    }
    this.soldierSubweaponCall={body:body,token:body.soldierToken,owner:owner,state:this.长枪副武器状态,weapon:this.长枪副武器};
    this.cf6CurrentFireBit=8;this.动作B=true;
    _global.org.flashNight.arki.unit.Action.Shoot.ShootCore.continuousShootAs(this,context,context.interval);
    this.动作B=false;this.cf6CurrentFireBit=0;this.soldierSubweaponCall=null;
};
cf6FixedIdleReload=function():Void {
    if(this.soldierAttackOwner!=null || this.cf6Observation.interrupted)return;
    if(this.长枪.value.shot>=this.长枪弹匣容量)this.cf6ReloadRequested="长枪";
    else if(this.soldierPhase==2 && this.soldierIsElite){
        if(this.手枪.value.shot>=this.手枪弹匣容量)this.cf6ReloadRequested="手枪";
        else if(this.手枪2.value.shot>=this.手枪2弹匣容量)this.cf6ReloadRequested="手枪2";
    }
};
cf6FixedReload=function(slot:String):Void {
    if(this.cf6Observation.interrupted || !(this.hp>0) || this.soldierPhase==0){this.cf6ReloadRequested="";return;}
    var mode:String=slot=="长枪"?"primary":"dual";
    this.cf6FixedEnsurePose(mode);this.cf6FixedDrivePose();
    if(!this.cf6FixedModeReady(mode))return;
    var owner:Object=this.soldierAttackOwner;
    this.cf6ReloadRequested="";owner.reloadReceiptCommitted=false;
    this.standardShotMoving=false;
    if(this.man.cf6Stride!=null)this.man.cf6Stride.gotoAndStop(1);
    this.cf6Signals.event(this,"reload");
    if(mode=="dual")this.eliteBeginReload(this.man,slot);
    else{
        owner.reload=true;owner.reloadSlot="长枪";this.动作A=false;this.动作B=false;
        if(this.cf6Profile.program.trigger=="relocate_then_flush")this.soldierBeginSmokeReload(this.man);
        this.man.开始换弹();
    }
};
cf6FixedMoveReload=function(owner:Object):Void {
    if(!owner.smokeUsed || owner.reloadMoveBlocked || owner.reloadMovedX>=120
        || owner.reloadLastMoveFrame===this.cf6Observation.frame)return;
    owner.reloadLastMoveFrame=this.cf6Observation.frame;
    var amount:Number=Math.min(5,120-owner.reloadMovedX);
    var remainingTether:Number=this.cf6Profile.program.tether
        -owner.reloadMoveSign*(this._x-this.cf6ActionRecord.birthX);
    amount=Math.min(amount,Math.max(0,remainingTether));
    var before:Number=this._x;
    if(amount>0)this.soldierTacticalMove(owner.reloadMoveSign<0?"左":"右",amount);
    var moved:Number=Math.abs(this._x-before);owner.reloadMovedX+=moved;
    if(moved<.1)owner.reloadMoveBlocked=true;
    this.standardShotMoving=false;
};
cf6FixedReloadEnd=function(body:MovieClip):Void {
    var owner:Object=this.soldierAttackOwner;
    if(!owner.fixed){
        if(this.soldierIsElite)this.cf6LegacyEliteReloadEnd(body);else this.cf6LegacyReloadEnd(body);return;
    }
    if(!this.cf6FixedCanAct(body) || !owner.reload)return;
    this.soldierSubweaponReloadCommitted(body);
    if(owner.elite)_root.主角函数.取消混合换弹.call(body);
    else body.结束换弹();
    if(this.cf6Profile.program.trigger=="relocate_then_flush"){
        // The actual ammo commit supplies the token. Reveal begins only after
        // the old smoke's bounded fade; the program then holds 18 clear frames.
        this.cf6ActionRecord.reloadNotBefore=this.cf6ActionApi.now()+(owner.smokeUsed?13:0);
        if(owner.smokeUsed)this.soldierTacticalStats.smokeReloads++;
    }
    owner.reload=false;owner.completed=true;
    this.cf6PoseSwitch=true;this.cf6LegacyCancel();this.cf6LegacyState("长枪站立");this.cf6PoseSwitch=false;
};
cf6FixedBeginThrow=function(body:MovieClip):Void {
    if(this.cf6ExpectedPose!="throw"){this.cf6LegacyGrenadeBegin(body);return;}
    var owner:Object=this.cf6FixedOwner(body,"throw");owner.action="grenade";body.stop();
};
cf6FixedThrow=function(body:MovieClip):Void {
    if(this.cf6ExpectedPose!="throw")return;
    var s:Object=this.cf6ActionState,o:Object=this.cf6Observation;
    this.cf6ActionApi.observe(this.cf6ActionRecord,_root.gameworld[this.攻击目标],o);
    o.readyMode="throw";o.modeReady=this.cf6FixedModeReady("throw");
    if(!this.cf6RuleCanCommit(s,this.cf6Profile,o,16,2) || !this.cf6FixedCanAct(body))return;
    if(this.soldierAttackOwner.throwInProgress)return;
    this.soldierAttackOwner.throwInProgress=true;
    body.gotoAndStop(25);
    var data:Object=_root.getItemData(this.特种兵投掷物).data;
    if(!(data.power>0) || typeof data.bullet!="string")return;
    var release:Object={x:0,y:0};body.投掷手.localToGlobal(release);_root.gameworld.globalToLocal(release);
    var gravity:Number=Number(_root.重力加速度);if(!(gravity>0))gravity=1;
    var height:Number=Math.max(1,this.Z轴坐标-release.y);
    var flight:Number=(5+Math.sqrt(25+2*height*gravity))/gravity;
    var velocity:Number=Math.min(Number(data.velocity)>0?Number(data.velocity):25,Math.max(4,Math.abs(s.aimX-release.x)/flight));
    var group:Object=this.cf6Groups.begin(this.cf6ActionRecord,s.cycle);if(group==null)return;
    this.cf6RuleCommitted(s,this.cf6Profile,o,16,2);
    _root.子弹区域shoot传递({声音:"",霰弹值:1,子弹散射度:0,发射效果:"",子弹种类:data.bullet,
        子弹威力:Number(data.power),子弹速度:velocity,速度X:s.aimSign*velocity,速度Y:0,
        子弹大小:data.bulletsize,Z轴攻击范围:10,击倒率:10,发射者:this._name,发射者名:this._name,
        子弹敌我属性值:this.是否为敌人,shootX:release.x,shootY:release.y,shootZ:this.Z轴坐标,
        击中地图效果:"",击中后子弹的效果:"",cf6DamageGroup:group});
    this.cf6Groups.seal(group);this.soldierGrenadeCount++;body.play();
};
