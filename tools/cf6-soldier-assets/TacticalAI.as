// Shared CF6 tactical parameters are copied once at spawn. External scalar
// overrides use 特种兵战术_<key>; changing a test case never mutates another unit.
soldierTacticalStats={wallEscapes:0,slideBlocks:0,slideStalls:0,smokes:0,smokeReloads:0,slideExits:0,chargeContacts:0,chargeHits:0,chargeDamage:0,chargeTurns:0,evasions:0,blockedMoves:0,strategyChanges:0};
soldierNextEvasionAt=0;soldierNextEvasionAttemptAt=0;soldierPendingEvasion=null;soldierThreatOwned=false;
soldierSmokeNextAt=0;soldierSlidePermit=null;soldierRecentDamageUntil=0;
soldierStrategy="line";soldierStrategyUntil=0;soldierBlockedUntil=0;
soldierConfigureTactics=function():Void {
    var role:String=this.soldierIsInstructor===true?"instructor":this.soldierIsElite===true?"elite":"ordinary";
    var defaults:Object=cf6TacticalDefaults[role],limits:Object=cf6TacticalLimits;
    var config:Object={};this.soldierTacticalConfigErrors=0;
    for(var key:String in defaults){
        var supplied=this["特种兵战术_"+key];
        var value:Number=supplied==undefined?defaults[key]:Number(supplied);
        var bound:Array=limits[key];
        if(!isFinite(value) || value<bound[0] || value>bound[1]){
            value=defaults[key];this.soldierTacticalConfigErrors++;
        }
        config[key]=value;
    }
    this.soldierTacticalConfig=config;this.soldierTacticalRole=role;
    this.soldierTacticalPolicy=String(this.特种兵策略);
    if(this.soldierTacticalPolicy!="line" && this.soldierTacticalPolicy!="mobile"
        && this.soldierTacticalPolicy!="switch")this.soldierTacticalPolicy="adaptive";
    this.soldierTuning.burstShots=config.rifleShots;
    this.soldierTuning.maximumFireFrames=config.rifleFireFrames;
    this.soldierTuning.shootRestFrames=config.rifleRestFrames;
    this.soldierTuning.chargeRange=config.chargeRange;
    this.soldierTuning.chargeStopRange=config.chargeStopRange;
    this.soldierTuning.chargeStageRange=config.chargeMinRange;
    this.soldierLastObservedHP=this.hp;
    if(this.特种兵烟雾弹==undefined)this.特种兵烟雾弹=this.soldierIsElite===true;
    if(this.特种兵避弹==undefined)this.特种兵避弹=this.soldierIsElite===true;
    // Reuse the main runtime's scanner. Do not publish a second class singleton.
    this.soldierThreatApi=_global.org.flashNight.arki.bullet.BulletComponent.Queue.BulletThreatScanProcessor;
    if(this.特种兵避弹===true && this._btEnabled!==true && typeof this.soldierThreatApi.register=="function"){
        this.soldierThreatApi.register(this);this.soldierThreatOwned=true;
    }
};
soldierTacticalObserve=function():Void {
    if(this.hp<this.soldierLastObservedHP)this.soldierRecentDamageUntil=this.soldierClock+45;
    this.soldierLastObservedHP=this.hp;
    if(this.特种兵战术诊断===true && typeof _root.服务器.发布服务器消息=="function"){
        if(!this.soldierPanelReported && this.soldierClock>=6){
            this.soldierPanelReported=true;
            _root.服务器.发布服务器消息("[CF6-TACTICAL-PANEL] unit="+this._name+" role="+this.soldierTacticalRole
                +" policy="+this.soldierTacticalPolicy+" phase="+this.soldierPhase+" enemy="+this.是否为敌人
                +" maxHp="+this.hp满血值+" defense="+this.防御力+" melee="+this.空手攻击力
                +" toughness="+this.韧性系数+" speedX="+this.行走X速度+" speedZ="+this.行走Y速度
                +" hit="+this.命中率+" dodge="+this.躲闪率+" riflePower="+this.长枪属性.power
                +" rifleInterval="+this.长枪属性.interval+" pistolPower="+this.手枪属性.power
                +" offhandPower="+this.手枪2属性.power+" damageTaken="+this.damageTakenMultiplier);
        }
        if(this.soldierClock%90==0 || this.hp<=0){
            var stats:Object=this.soldierTacticalStats;
            _root.服务器.发布服务器消息("[CF6-TACTICAL-STATE] unit="+this._name+" phase="+this.soldierPhase
                +" strategy="+this.soldierStrategy+" smoke="+stats.smokes+" reloaded="+stats.smokeReloads
                +" exits="+stats.slideExits+" contact="+stats.chargeContacts+" blocked="+stats.blockedMoves
                +" hits="+stats.chargeHits+" impactDamage="+stats.chargeDamage+" turns="+stats.chargeTurns
                +" evasions="+stats.evasions+" wallEscapes="+stats.wallEscapes+" slideBlocks="+stats.slideBlocks+" slideStalls="+stats.slideStalls+" bt="+this._btCount+" switches="+stats.strategyChanges
                +" shots="+this.soldierShotCount+" sub="+this.soldierSubweaponShots
                +" subReload="+this.soldierSubweaponReloads+" subLoaded="+this.长枪副武器状态.loaded+" hp="+this.hp);
        }
    }
    if(this.hp<=0)this.soldierReleaseTactics();
};
soldierSelectStrategy=function(dx:Number,dz:Number):String {
    if(this.soldierIsInstructor!==true)return this.soldierIsElite===true?"mobile":"line";
    var policy:String=this.soldierTacticalPolicy;
    if(policy=="line" || policy=="mobile")return policy;
    if(policy=="switch")return dx<260 || dz>24?"mobile":"line";
    if(this.soldierClock<this.soldierStrategyUntil)return this.soldierStrategy;
    var target:MovieClip=_root.gameworld[this.攻击目标];
    var pressure:Boolean=this.soldierClock<this.soldierRecentDamageUntil;
    var lineScore:Number=(dx>180 && dz<=24?4:0)+(pressure?0:2);
    var mobileScore:Number=(dx<180?5:0)+(pressure?4:0)+(dz>36?2:0);
    var rifleLoaded:Boolean=this.长枪.value.shot<this.长枪弹匣容量;
    var pistolLoaded:Boolean=this.手枪.value.shot<this.手枪弹匣容量
        || (this.eliteSidearmEnabled() && this.手枪2.value.shot<this.手枪2弹匣容量);
    if(!rifleLoaded && pistolLoaded)mobileScore+=4;
    if(rifleLoaded && !pistolLoaded)lineScore+=4;
    if(this.soldierClock<this.soldierBlockedUntil)mobileScore-=4;
    var next:String=mobileScore>lineScore+1?"mobile":"line";
    if(next!=this.soldierStrategy)this.soldierTacticalStats.strategyChanges++;
    this.soldierStrategy=next;
    this.soldierStrategyUntil=this.soldierClock+this.soldierTacticalConfig.strategyHoldFrames;
    return next;
};
soldierTacticalChoose=function(dx:Number,dz:Number,height:Number):String {
    var config:Object=this.soldierTacticalConfig,tune:Object=this.soldierTuning;
    if(!isFinite(dx) || !isFinite(dz) || !isFinite(height) || dx<0 || dz<0
        || height>tune.maximumTargetHeight || this.soldierClock<this.soldierReadyAt)return "none";
    var strategy:String=this.soldierSelectStrategy(dx,dz);
    // A committed smoke reload hands directly to the slide; it does not
    // wait for a new AI decision or borrow the ordinary running prelude.
    // Point-blank instructor defence takes precedence over strategy and bullet evasion.
    if(this.soldierIsInstructor===true && dx<=tune.knifeRange && dz<=tune.laneRange
        && !(this.soldierClock<this.soldierNextMeleeAt)){
        this.soldierMeleeKind=this.soldierPhase==1 && dx<=tune.bashRange
            && !(this.soldierClock<this.soldierNextBashAt)?"bash":"knife";
        return "knife";
    }
    if(this.soldierTryEvasion(dx,dz))return "shoot";
    if(this.soldierPhase==1 && this.soldierIsElite===true){
        if(dz>tune.laneRange)return "none";
        // Close defence is shared by both instructor strategies. A mobile
        // commitment must not suppress the shield/knife after a charge.
        if(this.soldierIsInstructor===true && dx<=tune.knifeRange){
            if(this.soldierClock<this.soldierNextMeleeAt)return "none";
            this.soldierMeleeKind=dx<=tune.bashRange && !(this.soldierClock<this.soldierNextBashAt)?"bash":"knife";
            return "knife";
        }
        if(dx<config.chargeMinRange || dx>config.chargeRange || this.soldierClock<this.soldierNextShootAt)return "none";
        this.soldierShieldCoverFire=this.soldierIsInstructor===true && strategy=="line" && dx>tune.knifeRange;
        this.eliteNextAction=this.soldierShieldCoverFire?"line":"stand";
        return "shoot";
    }
    if(this.soldierIsElite!==true || this.soldierIsInstructor===true){
        if(dx>=180 && dx<=480 && dz<=80 && !(this.soldierClock<this.soldierNextGrenadeAt)
            && this.soldierCanGrenade() && (strategy=="line" || dz>tune.laneRange))return "grenade";
        if(dx<=tune.knifeRange && dz<=tune.laneRange && !(this.soldierClock<this.soldierNextMeleeAt)
            && (strategy=="line" || this.soldierClock<this.soldierBlockedUntil)){
            this.soldierMeleeKind=this.soldierPhase==1 && dx<=tune.bashRange
                && !(this.soldierClock<this.soldierNextBashAt)?"bash":"knife";
            return "knife";
        }
    }
    if(dx>tune.shootRange || dz>tune.laneRange || this.soldierClock<this.soldierNextShootAt)return "none";
    this.eliteNextAction=this.soldierIsInstructor===true && strategy=="line"?"line":
        strategy=="mobile" && !(this.soldierClock<this.soldierBlockedUntil)?(dx<config.retreatTrigger?"retreat":
            dx>config.runTrigger?"run":"stand"):"stand";
    if(this.soldierIsElite===true && (!this.eliteTactics || !this.eliteMobility))this.eliteNextAction="stand";
    return "shoot";
};
soldierTacticalMove=function(direction:String,speed:Number):Number {
    if(!(speed>0) || !isFinite(speed))return 0;
    var beforeX:Number=this._x,beforeZ:Number=this.Z轴坐标;
    this.移动(direction,speed);
    var travelled:Number=Math.abs(this._x-beforeX)+Math.abs(this.Z轴坐标-beforeZ);
    if(travelled<0.1){this.soldierTacticalStats.blockedMoves++;this.soldierBlockedUntil=this.soldierClock+24;}
    return travelled;
};
soldierBeginSmokeReload=function(body:MovieClip):Void {
    var owner:Object=this.soldierAttackOwner,config:Object=this.soldierTacticalConfig;
    if(owner==null || owner.smokePrepared || this.soldierPhase!=2)return;
    owner.smokePrepared=true;owner.reloadMoveAge=0;owner.reloadMovedX=0;owner.reloadMovedZ=0;
    var target:MovieClip=_root.gameworld[this.攻击目标];
    owner.reloadMoveSign=target._x<this._x?1:-1;
    var dz:Number=target.Z轴坐标-this.Z轴坐标;
    owner.reloadZSign=Math.abs(dz)>24?(dz<0?-1:1):this.eliteStrafeSign;
    if(this.特种兵烟雾弹===false || this.soldierClock<this.soldierSmokeNextAt)return;
    this.soldierSmokeNextAt=this.soldierClock+config.smokeRestFrames;
    owner.smokeUsed=true;owner.smokeTarget=target;
    var world:MovieClip=_root.gameworld;
    var depth:Number=world.getNextHighestDepth();
    var cloud:MovieClip=world.attachMovie("CF6战术烟雾","cf6Smoke"+depth,depth,
        {_x:this._x,_y:this.Z轴坐标-30,sourceUnit:this,sourceOwner:owner,smokeAge:0});
    if(cloud==null){owner.smokeUsed=false;this.soldierWeaponError="CF6 smoke linkage is unavailable";return;}
    owner.smokeCloud=cloud;
    this.soldierTacticalStats.smokes++;
};
soldierMoveSmokeReload=function(owner:Object,body:MovieClip):Void {
    // Reload has a planted, concealed pose. Running belongs to its own attack.
    this.standardShotMoving=false;
};
soldierCanSlideExit=function(target:MovieClip):Boolean {
    if(this.soldierPhase!=2 || !(target.hp>0) || target!==_root.gameworld[this.攻击目标]
        || this.倒地 || this.浮空 || this.soldierClock<this.soldierBlockedUntil)return false;
    var dx:Number=Math.abs(target._x-this._x),dz:Number=Math.abs(target.Z轴坐标-this.Z轴坐标);
    return isFinite(dx) && isFinite(dz) && this.eliteMobility && this.跑X速度>0
        && dx<=this.soldierTuning.shootRange
        && dz<=this.soldierTuning.laneRange+Math.min(this.soldierTacticalConfig.slideZBudget,60)
        && this.eliteWeaponReady("长枪") && this.长枪.value.shot<this.长枪弹匣容量;
};
soldierCompleteSmokeReload=function(owner:Object):Void {
    if(!owner.smokeUsed || !owner.active || this.soldierPhase!=2)return;
    this.soldierTacticalStats.smokeReloads++;
    this.soldierSlidePermit={target:owner.smokeTarget,expiresAt:this.soldierClock+this.soldierTacticalConfig.slidePermitFrames};
};
soldierChargeContact=function(owner:Object):Boolean {
    if(owner.contactCommitted)return false;
    var target:MovieClip=_root.gameworld[owner.target];
    if(!(target.hp>0) || target.area==null || Math.abs(target.Z轴坐标-this.Z轴坐标)>this.soldierTuning.laneRange)return false;
    var world:MovieClip=_root.gameworld,config:Object=this.soldierTacticalConfig;
    var ownBounds:Object=this.area.getBounds(world),targetBounds:Object=target.area.getBounds(world);
    var front:Number=this._x+owner.sign*config.chargeContactReach;
    var left:Number=owner.sign>0?Math.min(owner.lastChargeX,this._x)+12:front;
    var right:Number=owner.sign>0?front:Math.max(owner.lastChargeX,this._x)-12;
    // Broad-phase damage rejects touching edges. Require positive overlap before
    // spending the action's one contact; otherwise the impact can silently miss.
    if(Math.min(right,targetBounds.xMax)-Math.max(left,targetBounds.xMin)<2
        || Math.min(ownBounds.yMax,targetBounds.yMax)-Math.max(ownBounds.yMin,targetBounds.yMin)<2)return false;
    owner.contactCommitted=true;owner.contactAge=owner.age;
    var depth:Number=world.getNextHighestDepth();
    var area:MovieClip=world.createEmptyMovieClip("cf6ChargeArea"+depth,depth);
    this.soldierChargeArea=area;area.age=0;
    area.onEnterFrame=function():Void {if(!_root.暂停 && ++this.age>2)this.removeMovieClip();};
    var points:Array=[{x:left,y:ownBounds.yMin},{x:right,y:ownBounds.yMin},{x:right,y:ownBounds.yMax},{x:left,y:ownBounds.yMax}];
    area.beginFill(0,0);
    for(var i:Number=0;i<4;i++){
        var point:Object=points[i];
        if(i==0)area.moveTo(point.x,point.y);else area.lineTo(point.x,point.y);
    }
    area.lineTo(points[0].x,points[0].y);area.endFill();
    if(this.特种兵战术诊断===true && target.dispatcher!=null){
        this.soldierReleaseChargeObserver();this.soldierChargeDispatcher=target.dispatcher;
        target.dispatcher.subscribe("hit",this.soldierObserveChargeHit,this);
    }
    var bullet:MovieClip=_root.子弹区域shoot传递({声音:"",霰弹值:1,子弹散射度:0,发射效果:"",子弹种类:"近战子弹",
        子弹威力:this.空手攻击力*config.chargePower,子弹速度:0,暴击:function(bullet:Object):Number {return 1;},
        斩杀:0,Z轴攻击范围:this.soldierTuning.laneRange,发射者:this._name,
        shootX:this._x,shootY:this._y,shootZ:this.Z轴坐标,击倒率:6,
        击中地图效果:"",击中后子弹的效果:"空手攻击火花",水平击退速度:config.chargePush,
        垂直击退速度:0,区域定位area:area});
    if(bullet!=null){bullet.cf6ChargeSource=this;bullet.cf6ChargeToken=owner.token;}
    this.soldierTacticalStats.chargeContacts++;
    return true;
};
soldierObserveChargeHit=function(target:MovieClip,shooter:MovieClip,bullet:MovieClip,collision:Object,result:Object):Void {
    if(shooter!==this || bullet.cf6ChargeSource!==this || bullet.cf6ChargeToken!==this.soldierAttackOwner.token)return;
    var damage:Number=Number(target.损伤值);
    this.soldierTacticalStats.chargeHits++;
    if(isFinite(damage) && damage>0)this.soldierTacticalStats.chargeDamage+=damage;
    if(typeof _root.服务器.发布服务器消息=="function")
        _root.服务器.发布服务器消息("[CF6-CHARGE-HIT] unit="+this._name+" target="+target._name
            +" damage="+damage+" targetHp="+target.hp+" status="+result.dodgeStatus);
};
soldierReleaseChargeObserver=function():Void {
    if(this.soldierChargeDispatcher!=null){
        this.soldierChargeDispatcher.unsubscribe("hit",this.soldierObserveChargeHit,this);
        this.soldierChargeDispatcher=null;
    }
};
soldierReleaseTactics=function():Void {
    this.soldierReleaseChargeObserver();this.soldierPendingEvasion=null;
    if(this.soldierThreatOwned && typeof this.soldierThreatApi.unregister=="function"){
        this.soldierThreatApi.unregister(this);this.soldierThreatOwned=false;
    }
};
soldierEvasionZSign=function():Number {
    var data:Object=this.unitAI.data;
    var resolver:Object=_global.org.flashNight.arki.unit.UnitAI.combat.MovementResolver;
    if(isFinite(data.bndUpDist) && isFinite(data.bndDownDist) && typeof resolver.pickZDirBySpaceEx=="function"){
        var picked:Number=resolver.pickZDirBySpaceEx(data,this,24);
        return picked<0?-1:picked>0?1:0;
    }
    // Native fixtures may not create the generic AI. Bounds remain authoritative.
    var up:Number=this.Z轴坐标-Number(_root.Ymin),down:Number=Number(_root.Ymax)-this.Z轴坐标;
    if(isFinite(up) && isFinite(down)){
        if(up<24 && down<24)return 0;
        return up>down?-1:1;
    }
    return this.eliteStrafeSign<0?-1:1;
};
soldierTryEvasion=function(dx:Number,dz:Number):Boolean {
    var config:Object=this.soldierTacticalConfig;
    if(!isFinite(dx) || !isFinite(dz) || this.soldierIsElite!==true || this.soldierPhase!=2 || this.特种兵避弹!==true
        || !this.eliteTactics || !this.eliteMobility || this.soldierClock<this.soldierNextEvasionAttemptAt
        || this.soldierTacticalPolicy=="line" || this.倒地 || this.浮空
        || dx>this.soldierTuning.shootRange || dz>80
        || !this.elitePrimaryPistolEnabled())return false;
    var target:MovieClip=_root.gameworld[this.攻击目标];
    if(!(target.hp>0))return false;
    var pending:Object=this.soldierPendingEvasion;
    if(pending!=null && (pending.target!==target || this.soldierClock>pending.until)){
        this.soldierPendingEvasion=null;pending=null;
    }
    var wallEscape:Boolean=pending!=null && pending.noFire===true
        && (pending.reason=="slide_blocked" || pending.reason=="slide_stalled");
    if((this.硬直中 || this.soldierClock<this.soldierNextEvasionAt) && !wallEscape)return false;
    var age:Number=_root.帧计时器.当前帧数-this._btFrame;
    var fresh:Boolean=isFinite(age) && age>=0 && age<=1 && this._btCount>0
        && this._btMinETA>=0 && this._btMinETA<config.evasionETA;
    if(pending==null && !fresh)return false;
    if(pending==null)this.soldierPendingEvasion={target:target,until:this.soldierClock+8,zSign:this.soldierEvasionZSign()};
    this.eliteNextAction="retreat";
    return true;
};
soldierInstallTactics=function():Void {
    this.soldierConfigureTactics();
    this.soldierChooseAttack=this.soldierTacticalChoose;
    this.soldierInstallSubweapon();
};
