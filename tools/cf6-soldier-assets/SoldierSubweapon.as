// NPC-only secondary lane. Never consult or consume the player's inventory.
soldierSubweaponShots=0;soldierSubweaponReloads=0;soldierSubweaponNextAt=0;
soldierSubweaponAllowed=function():Boolean {
    return this.特种兵副武器!==false && this._name!==_root.控制目标
        && this._name!==_root.主角名 && this.soldierPhase>0;
};
soldierSubweaponReady=function(body:MovieClip):Boolean {
    var owner:Object=this.soldierAttackOwner;
    return this.soldierSubweaponAllowed() && this.soldierCanAct(body) && !this.倒地 && !this.浮空
        && !this.硬直中 && owner.action=="shoot" && !owner.reload && owner.kind!="retreat"
        && owner.weapon===this.长枪 && this.长枪副武器状态!=null
        && body.soldierToken===owner.token;
};
soldierSubweaponCommitCost=function(unit:Object,slot:String,props:Object):Boolean {
    var config:Object=unit.长枪副武器配置,state:Object=unit.长枪副武器状态;
    if(!unit.soldierSubweaponReady(unit.man) || state!==unit.soldierSubweaponCall.state
        || unit.soldierAttackOwner!==unit.soldierSubweaponCall.owner
        || unit.man!==unit.soldierSubweaponCall.body)return false;
    if(config.hp>0 && !(unit.hp>config.hp))return false;
    if(config.mp>0 && !(unit.mp>=config.mp))return false;
    if(state.fireGuard!==undefined && (typeof state.fireGuard!="function" || state.fireGuard(unit)!==true))return false;
    if(config.hp>0)unit.hp-=config.hp;
    if(config.mp>0)unit.mp-=config.mp;
    state.groupPaid=true;
    return true;
};
soldierSubweaponFire=function(marker:MovieClip,props:Object):Boolean {
    var call:Object=this.soldierSubweaponCall,body:MovieClip=this.man;
    var owner:Object=this.soldierAttackOwner,state:Object=this.长枪副武器状态;
    if(call==null || !this.soldierSubweaponReady(body) || call.body!==body || call.owner!==owner
        || call.token!==body.soldierToken || call.state!==state || call.weapon!==this.长枪副武器
        || owner.subweaponFired || marker==null || marker!==this.soldierMuzzleMarker(body)
        || this.soldierClock<this.soldierSubweaponNextAt || getTimer()<state.nextFireTime)return false;
    var api:Object=_global.org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
    if(!(api.getLoadedCount(this)>0) || props==null)return false;
    delete props.区域定位area;
    // The interceptable projectile is a genuine child of this shooter. Existing
    // calibration attribution validates this source against the active roster.
    props.产生源=this._name;
    var fired:Boolean=_global.org.flashNight.arki.unit.Action.Shoot.WeaponFireCore.executeShot(
        this,"长枪副武器",marker,props,this.soldierSubweaponCommitCost);
    if(!fired)return false;
    owner.subweaponFired=true;this.soldierSubweaponShots++;
    var cd:Number=this.长枪副武器配置.cd;
    state.nextFireTime=getTimer()+cd;
    this.soldierSubweaponNextAt=this.soldierClock+Math.max(1,Math.ceil(cd*30/1000));
    api.syncSnapshots(this);
    return true;
};
soldierDriveSubweapon=function(body:MovieClip):Void {
    var owner:Object=this.soldierAttackOwner;
    if(!this.soldierSubweaponReady(body) || owner.subweaponFired || owner.subweaponFirstShotAt==undefined
        || this.soldierClock<owner.subweaponFirstShotAt+6 || this.soldierClock<this.soldierSubweaponNextAt)return;
    var target:MovieClip=_root.gameworld[owner.target];
    var dx:Number=(target._x-this._x)*(this.方向=="左"?-1:1);
    var dz:Number=Math.abs(target.Z轴坐标-this.Z轴坐标);
    if(!(target.hp>0) || !(dx>=120 && dx<=this.soldierTuning.shootRange) || !(dz<=this.soldierTuning.laneRange)
        || this.soldierMuzzleMarker(body)==null)return;
    var api:Object=_global.org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
    if(typeof api.buildShootContext!="function" || !(api.getLoadedCount(this)>0))return;
    var context:Object=api.buildShootContext(this);
    context.man=body;context.refreshManEachTick=false;context.fireMethodName="soldierSubweaponFire";
    this.soldierSubweaponCall={body:body,token:body.soldierToken,owner:owner,
        state:this.长枪副武器状态,weapon:this.长枪副武器};
    this.动作B=true;
    _global.org.flashNight.arki.unit.Action.Shoot.ShootCore.continuousShootAs(this,context,context.interval);
    this.动作B=false;this.soldierSubweaponCall=null;
};
soldierSubweaponReloadCommitted=function(body:MovieClip):Void {
    var owner:Object=this.soldierAttackOwner;
    if(!this.soldierSubweaponAllowed() || !this.soldierCanAct(body) || !owner.reload || owner.subweaponReloaded
        || owner.weapon!==this.长枪 || (owner.reloadSlot!=null && owner.reloadSlot!="长枪")
        || this.长枪.value.shot!==0)return;
    owner.subweaponReloaded=true;
    if(_global.org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore.reloadLinkedFree(this))this.soldierSubweaponReloads++;
};
soldierWrapReloadCommit=function(body:MovieClip):Void {
    if(body.soldierOriginalMagazineCommit!=null || typeof body.换弹匣!="function")return;
    body.soldierOriginalMagazineCommit=body.换弹匣;
    body.换弹匣=function():Void {
        var unit:MovieClip=this._parent,owner:Object=unit.soldierAttackOwner;
        if(!unit.soldierCanAct(this) || !owner.reload || owner.weapon!==unit.长枪
            || (owner.reloadSlot!=null && owner.reloadSlot!="长枪"))return;
        this.soldierOriginalMagazineCommit();
        unit.soldierSubweaponReloadCommitted(this);
    };
};
soldierInstallSubweapon=function():Void {
    this.soldierSubweaponPrimaryFire=this.长枪射击;
    this.长枪射击=function(marker:MovieClip,props:Object):Boolean {
        var fired:Boolean=this.soldierSubweaponPrimaryFire(marker,props);
        if(fired && this.soldierAttackOwner.subweaponFirstShotAt==undefined)
            this.soldierAttackOwner.subweaponFirstShotAt=this.soldierClock;
        return fired;
    };
    this.soldierSubweaponPrimaryDrive=this.soldierDriveShooting;
    this.soldierDriveShooting=function(body:MovieClip):Void {
        this.soldierWrapReloadCommit(body);
        this.soldierDriveSubweapon(body);
        this.soldierSubweaponPrimaryDrive(body);
    };
    this.soldierSubweaponPrimaryReloadEnd=this.soldierReloadEnd;
    this.soldierReloadEnd=function(body:MovieClip):Void {
        this.soldierSubweaponReloadCommitted(body);
        this.soldierSubweaponPrimaryReloadEnd(body);
    };
    if(this.soldierIsElite===true){
        this.soldierSubweaponEliteReloadEnd=this.eliteReloadEnd;
        this.eliteReloadEnd=function(body:MovieClip):Void {
            this.soldierSubweaponReloadCommitted(body);
            this.soldierSubweaponEliteReloadEnd(body);
        };
    }
};
