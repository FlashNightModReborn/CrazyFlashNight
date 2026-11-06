// Pressure is recorded independently of the current animation's interruptibility.
// These scalar transitions are also executed verbatim by the offline Node runner.
soldierShieldGuardPending=false;soldierShieldGuardRequestAt=0;soldierShieldGuardHits=0;
soldierShieldGuardLastHitAt=-1000;soldierShieldGuardBuffActive=false;
soldierShieldGuardCount=0;soldierShieldGuardFirstAt=-1;soldierShieldGuardThreatCount=0;
soldierShieldGuardBuffSource="CF6特种兵架盾";
soldierTuning.shieldGuardTriggerRatio=0.025;
soldierTuning.shieldGuardHitWindow=12;soldierTuning.shieldGuardHitCount=3;
soldierTuning.shieldGuardRestFrames=90;soldierTuning.shieldGuardReductionPercent=85;
soldierTuning.shieldGuardHoldStart=13;soldierTuning.shieldGuardHoldEnd=50;
soldierTuning.shieldGuardThreatETA=12;

soldierInitializeDefense=function():Void {
    var key:String=typeof this.cf6UnitIdentity=="string"?this.cf6UnitIdentity:this._name;
    var hash:Number=0;
    for(var i:Number=0;i<length(key);i++)hash=(hash*31+key.charCodeAt(i))%65521;
    // Stable identity affects timing without consuming the game's random stream.
    this.soldierShieldGuardDelay=this.特种兵防御错峰===false?0:hash%5;
    this.soldierShieldGuardRatio=this.soldierTuning.shieldGuardTriggerRatio
        *(this.特种兵防御错峰===false?1:0.8+(hash%5)*0.1);
    this.soldierShieldGuardRest=this.soldierTuning.shieldGuardRestFrames
        +(this.特种兵防御错峰===false?0:(hash%7)*3);
    this.soldierShieldGuardProactive=this.特种兵主动架盾===true
        || (this.特种兵主动架盾!==false && hash%3==0);
};

soldierQueueShieldGuard=function(urgent:Boolean):Void {
    var ready:Number=this.soldierClock+(urgent?0:this.soldierShieldGuardDelay);
    if(!this.soldierShieldGuardPending || ready<this.soldierShieldGuardRequestAt)
        this.soldierShieldGuardRequestAt=ready;
    this.soldierShieldGuardPending=true;
};

soldierRecordShieldPressure=function(previous:Number,value:Number):Void {
    if(this.soldierPhase!=1 || !(value>0) || !isFinite(previous) || !isFinite(value)
        || !(previous>value) || !(this.hp满血值>0))return;
    var damage:Number=previous-value;
    this.soldierShieldGuardDamage+=damage;
    if(this.soldierClock-this.soldierShieldGuardLastHitAt>this.soldierTuning.shieldGuardHitWindow)
        this.soldierShieldGuardHits=0;
    this.soldierShieldGuardLastHitAt=this.soldierClock;
    this.soldierShieldGuardHits++;
    var threshold:Number=Math.max(1,this.hp满血值*this.soldierShieldGuardRatio);
    if(this.soldierShieldGuardDamage>=threshold
        || this.soldierShieldGuardHits>=this.soldierTuning.shieldGuardHitCount)
        this.soldierQueueShieldGuard(this.soldierShieldGuardDamage>=this.hp满血值*0.08);
};

soldierClearShieldPressure=function():Void {
    this.soldierShieldGuardPending=false;this.soldierShieldGuardDamage=0;
    this.soldierShieldGuardHits=0;this.soldierShieldGuardLastHitAt=-1000;
};

soldierEndShieldGuard=function():Void {
    if(this.cf6GuardImpactPending && this.soldierShieldGuardActive && this.soldierPhase==1
        && this.状态=="被击" && (this.man._currentframe==62 || this.man._currentframe==124))
        this.cf6Signals.event(this,"shield");
    this.cf6GuardImpactPending=false;
    this.soldierShieldGuardActive=false;
    if(this.soldierShieldGuardBuffActive){
        this.soldierShieldGuardBuffActive=false;
        _root.技能函数.移除霸体减伤(this,this.soldierShieldGuardBuffSource);
    }
};

soldierGuardPose=function(body:MovieClip,held:Boolean):Void {
    if(body!==this.man || this.soldierPhase!=1 || this.状态!="被击"
        || !this.soldierShieldGuardActive || !(this.hp>0))return;
    if(held){
        if(this.soldierShieldGuardBuffActive)return;
        if(this.buffManager==null || typeof _root.技能函数.霸体减伤!="function")return;
        this.soldierShieldGuardBuffActive=true;
        _root.技能函数.霸体减伤(this,this.soldierTuning.shieldGuardReductionPercent,0,this.soldierShieldGuardBuffSource);
    }else{
        if(!this.soldierShieldGuardBuffActive)return;
        this.soldierShieldGuardBuffActive=false;
        _root.技能函数.移除霸体减伤(this,this.soldierShieldGuardBuffSource);
    }
    // Timeline callbacks run outside the damage setter / BuffManager tick.
    this.buffManager.update(0);
};

soldierTryShieldGuard=function():Boolean {
    if(!this.soldierShieldGuardPending || this.soldierShieldGuardActive
        || this.soldierClock<this.soldierShieldGuardRequestAt || !this.soldierCanShieldGuard())return false;
    this.soldierClearShieldPressure();this.soldierShieldGuardActive=true;
    this.soldierShieldGuardCount++;
    if(this.soldierShieldGuardFirstAt<0)this.soldierShieldGuardFirstAt=this.soldierClock;
    this.soldierNextShieldGuardAt=this.soldierClock+this.soldierShieldGuardRest;
    this.soldierReadyAt=this.soldierClock;
    this.soldierClearMovement();
    // Preserve the weapon's existing ceasefire; defense cannot grant a free burst.
    this.状态改变("被击");
    return true;
};

soldierObserveShieldThreat=function():Void {
    if(!this.soldierShieldGuardProactive || this.soldierPhase!=1 || this.soldierShieldGuardActive
        || this.soldierClock<this.soldierNextShieldGuardAt || !(this._btCount>0))return;
    var age:Number=_root.帧计时器.当前帧数-this._btFrame;
    var eta:Number=this._btMinETA;
    if(!isFinite(age) || age<0 || age>1 || !isFinite(eta) || eta<0
        || !(eta<this.soldierTuning.shieldGuardThreatETA))return;
    this.soldierShieldGuardThreatCount++;
    this.soldierQueueShieldGuard(false);
};
