// CF6 身体接入标准长枪装备、射击和装填；攻击 token 只控制本单位动作所有权。
soldierClock=0;soldierReadyAt=6;soldierNextShootAt=0;soldierTargetName="";soldierAttackOwner=null;
soldierShotCount=0;soldierStabCount=0;soldierReloadCount=0;soldierInvalidMuzzleCount=0;
soldierWeaponError="";
soldierAlignZ=false;soldierApproachX=false;soldierMovementTarget="";
soldierShieldBuffSource="CF6特种兵持盾";soldierBuffError="";soldierShieldReduction=0;
soldierPhase=2;soldierPhaseChanges=0;soldierPhasePending=false;
soldierShieldStates={长枪站立:"持盾站立",长枪行走:"持盾行走",长枪跑:"持盾跑",
    长枪跳:"持盾被击",近战:"持盾近战",长枪攻击:"持盾攻击",拾取:"持盾站立",
    躲闪:"持盾站立",被击:"持盾被击",击倒:"持盾被击",倒地:"持盾被击",被投:"持盾被击"};
soldierTuning={shootRange:460,knifeRange:95,laneRange:24,keepDistance:190,
    reactionFrames:6,maximumTargetHeight:85,burstShots:3,recoveryFrames:4,
    maximumFireFrames:18,shootRestFrames:30,
    knifeCritChance:10,knifeCritMultiplier:6,knifeExecutePercent:5,secondLifeRatio:0.35,
    laneStopRange:12,approachStopRange:420,shieldDamageReductionPercent:75};

soldierClearMovement=function():Void {
    this.左行=this.右行=this.上行=this.下行=false;
    this.soldierAlignZ=this.soldierApproachX=false;
};

// Generic AI retains targeting. Only this policy supplies inputs consumed by walking.
soldierUpdateMovement=function():Void {
    this.左行=this.右行=this.上行=this.下行=false;
    var target:MovieClip=_root.gameworld[this.攻击目标];
    if(!(target.hp>0) || target===this || target.area==null){this.soldierClearMovement();return;}
    var dx:Number=target._x-this._x,dz:Number=target.Z轴坐标-this.Z轴坐标;
    if(isNaN(dx) || isNaN(dz)){this.soldierClearMovement();return;}
    if(this.soldierMovementTarget!=target._name){
        this.soldierAlignZ=this.soldierApproachX=false;this.soldierMovementTarget=target._name;
    }
    var tune:Object=this.soldierTuning,ax:Number=Math.abs(dx),az:Number=Math.abs(dz);
    if(az>tune.laneRange)this.soldierAlignZ=true;
    else if(az<=tune.laneStopRange)this.soldierAlignZ=false;
    if(ax>tune.shootRange)this.soldierApproachX=true;
    else if(ax<=tune.approachStopRange)this.soldierApproachX=false;
    this.上行=this.soldierAlignZ && dz<0;this.下行=this.soldierAlignZ && dz>0;
    this.左行=this.soldierApproachX && dx<0;this.右行=this.soldierApproachX && dx>0;
};

行走=function():Void {
    if(_root.暂停)return;
    if(_root.控制目标==this._name && _root.控制目标全自动==false){
        _root.敌人函数.行走.call(this);return;
    }
    if(!(this.hp>0) || this.soldierPhase==0 || this.浮空 || this.倒地 || this.硬直中
        || this.soldierAttackOwner!=null){this.soldierClearMovement();return;}
    if(this.状态!="长枪站立" && this.状态!="长枪行走" && this.状态!="长枪跑")return;
    // Re-evaluate at the movement consumer on every frame, after any generic AI write.
    this.soldierUpdateMovement();
    var target:MovieClip=_root.gameworld[this.攻击目标];
    var movingX:Boolean=this.左行 || this.右行,movingZ:Boolean=this.上行 || this.下行;
    var running:Boolean=movingX && Math.abs(target._x-this._x)>this.soldierTuning.shootRange;
    if(movingX){
        var direction:String=this.右行?"右":"左";this.方向改变(direction);
        var speedX:Number=running?this.跑X速度:this.行走X速度;
        this.移动(direction,Math.min(speedX,Math.max(0,Math.abs(target._x-this._x)-this.soldierTuning.approachStopRange)));
    }
    if(movingZ){
        var speedZ:Number=running?this.跑Y速度:this.行走Y速度;
        this.移动(this.下行?"下":"上",Math.min(speedZ,Math.max(0,Math.abs(target.Z轴坐标-this.Z轴坐标)-this.soldierTuning.laneStopRange)));
    }
    this.状态改变(movingX || movingZ?(running?"长枪跑":"长枪行走"):"长枪站立");
};

soldierApplyShieldBuff=function():Void {
    if(this.soldierPhase!=1)return;
    var reduction:Number=this.特种兵持盾减伤率==undefined?this.soldierTuning.shieldDamageReductionPercent:Number(this.特种兵持盾减伤率);
    if(isNaN(reduction) || reduction<0 || reduction>99){
        this.soldierBuffError="持盾减伤率须在 0 到 99 之间";trace("[CF6Soldier] "+this.soldierBuffError);
        reduction=this.soldierTuning.shieldDamageReductionPercent;
    }
    this.soldierShieldReduction=reduction;
    if(reduction==0)return;
    if(this.buffManager==null || typeof _root.技能函数.霸体减伤!="function"){
        this.soldierBuffError="持盾减伤的标准 Buff 入口缺失";trace("[CF6Soldier] "+this.soldierBuffError);return;
    }
    _root.技能函数.霸体减伤(this,reduction,0,this.soldierShieldBuffSource);
    this.buffManager.update(0);
};

soldierRemoveShieldBuff=function():Void {
    _root.技能函数.移除霸体减伤(this,this.soldierShieldBuffSource);
};

soldierCancelAttack=function():Void {
    if(this.soldierAttackOwner!=null) this.soldierAttackOwner.active=false;
    this.soldierAttackOwner=null;this.动作A=false;
    _root.主角函数.清理射击任务(this);
};

// Cancel before the timeline unloads its old man; delayed shots cannot adopt a new pose.
状态改变=function(next:String):Void {
    if(this.soldierPhase==0)return;
    if(this.soldierPhase==1 && (next=="血腥死" || next=="消失")){
        this.soldierSetHP(0);return;
    }
    if(this.状态==next)return;
    this.soldierCancelAttack();
    this.状态=next;
    this.gotoAndStop(this.soldierPhase==1?this.soldierShieldStates[next]:next);
};

soldierSetHP=function(value:Number):Void {
    if(isNaN(value))return;
    if(this.soldierPhase==0)return;
    if(this.soldierPhase==1 && value<=0){
        this.soldierHP=1;this.soldierPhase=0;this.soldierPhasePending=true;
        this.soldierPhaseChanges++;this.soldierCancelAttack();
        this.soldierClearMovement();this.soldierRemoveShieldBuff();
        return;
    }
    this.soldierHP=value;
};

soldierOnKill=function(target:MovieClip):Void {
    if(this.soldierPhase==1){this.soldierSetHP(0);return;}
    if(this.soldierPhase==0 || this._killed || this.hp>0)return;
    _root.敌人函数.标准击杀(this);
};

soldierInitializePhase=function():Void {
    var requested:Number=Number(this.特种兵初始阶段);
    if(requested!=1 && requested!=2){
        if(this.特种兵初始阶段!=undefined)trace("[CF6Soldier] invalid initial phase: "+this.特种兵初始阶段);
        requested=this.soldierDefaultPhase;
    }
    this.soldierPhase=this.soldierInitialPhase=requested;
    this.soldierNormalHitEffect=this.击中效果 || "飙血";
    this.击中效果=requested==1?"击中金属":this.soldierNormalHitEffect;
    this.soldierHP=Number(this.hp);
    this.soldierExternalRigid=this.刚体===true;
    this.soldierExternalInvincible=this.无敌===true;
    this.addProperty("hp",function():Number {return this.soldierHP;},
        function(value:Number):Void {this.soldierSetHP(Number(value));});
    this.addProperty("刚体",function():Boolean {return this.soldierPhase!=2 || this.soldierExternalRigid;},
        function(value:Boolean):Void {this.soldierExternalRigid=value===true;});
    this.addProperty("无敌",function():Boolean {return this.soldierPhase==0 || this.soldierExternalInvincible;},
        function(value:Boolean):Void {this.soldierExternalInvincible=value===true;});
    this.soldierStandardDeathCheck=this.死亡检测;
    this.死亡检测=function(para:Object):Void {
        if(this.soldierPhase!=2 || this.soldierDeathSettled)return;
        if(this.hp<=0)this.soldierDeathSettled=true;
        this.soldierStandardDeathCheck.call(this,para);
    };
    this.dispatcher.subscribeSingle("kill",this.soldierOnKill,this);
    this.soldierApplyShieldBuff();
    this.状态="";this.状态改变("长枪站立");
};

soldierBeginBreak=function():Void {
    if(this.soldierPhase!=0 || !this.soldierPhasePending)return;
    this.soldierPhasePending=false;
    this.soldierPhaseToken={};
    this.状态="破盾";this.gotoAndStop("破盾");
};

soldierFinishBreak=function(body:MovieClip):Void {
    if(_root.暂停 || this.soldierPhase!=0 || body!==this.man
        || body.soldierPhaseToken!==this.soldierPhaseToken)return;
    this.soldierPhase=2;this.soldierPhaseToken=null;
    // This timeline callback runs outside BuffManager.update. Flush only queued removals.
    if(this.buffManager!=null)this.buffManager.update(0);
    this.soldierShieldReduction=0;
    this.击中效果=this.soldierNormalHitEffect;
    this.soldierHP=Math.max(1,Math.round(this.hp满血值*this.soldierTuning.secondLifeRatio));
    this.浮空=this.倒地=this.硬直中=false;this.remainingImpactForce=0;
    this.soldierReadyAt=this.soldierClock+this.soldierTuning.reactionFrames;
    this.状态改变("长枪站立");
};

soldierBeginAttack=function(body:MovieClip,action:String):Void {
    this.soldierCancelAttack();
    if(!(this.hp>0)){body.stop();return;}
    var token:Object={};body.soldierToken=token;
    this.soldierAttackOwner={token:token,action:action,active:true,lastHitFrame:0,
        target:this.攻击目标,weapon:this.长枪,version:this.version,age:0,shots:0,recovery:0,reload:false};
    if(action=="shoot") {
        if(this.soldierClock<this.soldierNextShootAt){this.soldierFinishAttack(body);return;}
        if(!(this.长枪弹匣容量>0) || !(this.长枪属性.interval>0)
            || typeof _root.主角函数.初始化长枪射击函数!="function") {
            this.soldierWeaponError="长枪数据或标准射击入口缺失";
            trace("[CF6Soldier] "+this._name+" "+this.soldierWeaponError);
            this.soldierFinishAttack(body);return;
        }
        // The unit owns the deadline across pose changes, hits and target swaps.
        // No new attack or cancelled scheduler may reset the mandatory ceasefire.
        this.soldierAttackOwner.fireDeadline=this.soldierClock+this.soldierTuning.maximumFireFrames;
        this.soldierNextShootAt=this.soldierAttackOwner.fireDeadline+this.soldierTuning.shootRestFrames;
        body.初始化长枪射击函数=_root.主角函数.初始化长枪射击函数;
        body.初始化长枪射击函数();
    }
};

soldierCanAct=function(body:MovieClip):Boolean {
    var owner:Object=this.soldierAttackOwner;
    return !_root.暂停 && this.soldierPhase!=0 && this.hp>0 && !this.硬直中 && owner!=null && owner.active
        && body===this.man && body.soldierToken===owner.token && owner.version===this.version
        && (owner.action!="shoot" || owner.weapon===this.长枪)
        && this.状态==(owner.action=="knife"?"近战":"长枪攻击");
};

soldierFinishAttack=function(body:MovieClip):Void {
    var owner:Object=this.soldierAttackOwner;
    if(owner==null || body!==this.man || owner.token!==body.soldierToken)return;
    this.soldierCancelAttack();this.动画完毕();
};

soldierMuzzleMarker=function(body:MovieClip):MovieClip {
    var outer:MovieClip=body.枪,holder:MovieClip=outer.枪,gun:MovieClip=holder.装扮;
    var marker:MovieClip=gun.枪口位置;
    if(outer._parent!==body || holder._parent!==outer || gun._parent!==holder
        || marker._parent!==gun || gun!==this.长枪_引用)return null;
    return marker;
};

soldierMuzzle=function(body:MovieClip):Object {
    var marker:MovieClip=this.soldierMuzzleMarker(body);if(marker==null)return null;
    var p:Object={x:0,y:0};marker.localToGlobal(p);var globalY:Number=p.y;
    _root.gameworld.globalToLocal(p);if(isNaN(p.x) || isNaN(p.y))return null;
    p.globalY=globalY;return p;
};

// ShootCore chooses cadence and WeaponFireCore commits ammunition and bullet properties.
长枪射击=function(marker:MovieClip,props:Object):Boolean {
    var body:MovieClip=this.man,owner:Object=this.soldierAttackOwner;
    if(!this.soldierCanAct(body) || owner.action!="shoot" || owner.reload
        || owner.shots>=this.soldierTuning.burstShots
        || !(this.soldierClock<owner.fireDeadline))return false;
    if(marker!==this.soldierMuzzleMarker(body) || marker==null){this.soldierInvalidMuzzleCount++;return false;}
    var fired:Boolean=_root.主角函数.长枪射击.call(this,marker,props);
    if(fired){owner.shots++;this.soldierShotCount++;if(owner.shots>=this.soldierTuning.burstShots)this.动作A=false;}
    return fired;
};

soldierReloadStart=function(body:MovieClip):Void {
    if(!this.soldierCanAct(body)){body.stop();return;}
    this.动作A=false;this.soldierAttackOwner.reload=true;this.soldierReloadCount++;
    _root.主角函数.初始化换弹负担(body,15,35,18,49,[35,47]);
};

soldierReloadEnd=function(body:MovieClip):Void {
    if(!this.soldierCanAct(body)){body.stop();return;}
    body.结束换弹();this.soldierFinishAttack(body);
};

soldierDriveShooting=function(body:MovieClip):Void {
    var owner:Object=this.soldierAttackOwner;owner.age++;
    if(owner.reload){_root.主角函数.换弹帧率控制(body);return;}
    if(!(this.soldierClock<owner.fireDeadline)){this.soldierFinishAttack(body);return;}
    if(owner.shots>=this.soldierTuning.burstShots){
        if(++owner.recovery>=this.soldierTuning.recoveryFrames)this.soldierFinishAttack(body);
        return;
    }
    if(owner.age<3)return;
    if(this.soldierMuzzleMarker(body)==null){
        if(owner.age>30){this.soldierWeaponError="长枪外观或枪口引用缺失";
            trace("[CF6Soldier] "+this._name+" "+this.soldierWeaponError);this.soldierFinishAttack(body);}
        return;
    }
    this.动作A=true;body.开始射击();
};

soldierStab=function(body:MovieClip,point:MovieClip):Void {
    if(!this.soldierCanAct(body) || point.area==null) return;
    var owner:Object=this.soldierAttackOwner;
    if(owner.action!="knife" || owner.lastHitFrame==body._currentframe) return;
    owner.lastHitFrame=body._currentframe;
    var p:Object={x:point._x,y:point._y};body.localToGlobal(p);_root.gameworld.globalToLocal(p);
    this.soldierStabCount++;
    // Snapshot numbers, not the shooter's lifetime, into the standard crit callback.
    var critChance:Number=this.soldierTuning.knifeCritChance;
    var critMultiplier:Number=this.soldierTuning.knifeCritMultiplier;
    _root.子弹区域shoot传递({声音:"",霰弹值:1,子弹散射度:0,发射效果:"",
        子弹种类:"近战子弹",子弹威力:this.空手攻击力,子弹速度:0,
        暴击:function(bullet:Object):Number {return _root.成功率(critChance)?critMultiplier:1;},
        斩杀:this.soldierTuning.knifeExecutePercent,
        Z轴攻击范围:24,击中地图效果:"",发射者:this._name,
        shootX:p.x,shootY:p.y,shootZ:this.Z轴坐标,击倒率:10,
        击中后子弹的效果:"空手攻击火花",水平击退速度:2,垂直击退速度:1,
        区域定位area:point.area});
};

soldierChooseAttack=function(dx:Number,dz:Number,height:Number):String {
    var tune:Object=this.soldierTuning;
    if(isNaN(dx) || isNaN(dz) || isNaN(height) || dx<0 || dz<0
        || dz>tune.laneRange || height>tune.maximumTargetHeight || this.soldierClock<this.soldierReadyAt) return "none";
    if(dx<=tune.knifeRange) return "knife";
    if(dx<=tune.shootRange && !(this.soldierClock<this.soldierNextShootAt)) return "shoot";
    return "none";
};

soldierTick=function():Void {
    if(this.soldierPhase==0){
        if(_root.暂停)return;
        this.soldierBeginBreak();
        var body:MovieClip=this.man;
        if(body.soldierPhaseToken===this.soldierPhaseToken){
            if(body._currentframe>=11)this.soldierFinishBreak(body);
            else body.nextFrame();
        }
        return;
    }
    if(_root.暂停)return;
    this.soldierClock++;
    if(!isNaN(this.hp) && this.hp<=0){
        this.soldierCancelAttack();
        if(this.状态!="血腥死" && this.状态!="消失")this.状态改变("血腥死");
        return;
    }
    var owner:Object=this.soldierAttackOwner;
    if(owner!=null && !this.soldierCanAct(this.man)){
        this.soldierCancelAttack();
        if(this.状态=="长枪攻击" || this.状态=="近战")this.动画完毕();
        return;
    }
    if(!(this.hp>0) || this.倒地 || this.浮空 || this.硬直中)return;
    if(owner!=null){if(owner.action=="shoot")this.soldierDriveShooting(this.man);return;}
    if(_root.控制目标==this._name && _root.控制目标全自动==false)return;
    if(this.状态!="长枪站立" && this.状态!="长枪行走" && this.状态!="长枪跑")return;
    if((this.soldierClock&3)!=0)return;
    this.x轴攻击范围=0;this.y轴攻击范围=this.soldierTuning.laneRange;
    this.x轴保持距离=this.soldierTuning.keepDistance;
    if(this.unitAI.data!=null){
        this.unitAI.data.xrange=0;this.unitAI.data.zrange=this.y轴攻击范围;
        this.unitAI.data.xdistance=this.x轴保持距离;
    }
    var target:MovieClip=_root.gameworld[this.攻击目标];
    if(!(target.hp>0) || target==this || target.area==null)return;
    var dx:Number=target._x-this._x,dz:Number=target.Z轴坐标-this.Z轴坐标;
    var height:Number=target.Z轴坐标-target._y;
    if(target.浮空高度!=undefined && !isNaN(target.浮空高度) && target.浮空高度>0)height+=target.浮空高度;
    if(isNaN(dx) || isNaN(dz) || isNaN(height))return;
    if(this.soldierTargetName!=target._name){
        this.soldierTargetName=target._name;
        this.soldierReadyAt=this.soldierClock+this.soldierTuning.reactionFrames;
    }
    var action:String=this.soldierChooseAttack(Math.abs(dx),Math.abs(dz),height);
    if(action=="none"){
        this.soldierUpdateMovement();
        return;
    }
    this.soldierClearMovement();
    if(dx<0)this.方向改变("左");else if(dx>0)this.方向改变("右");
    this.状态改变(action=="knife"?"近战":"长枪攻击");
};
