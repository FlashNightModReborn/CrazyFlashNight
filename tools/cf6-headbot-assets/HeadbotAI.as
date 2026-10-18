// 悬浮机械单位：原稿双光束 / 四段伸缩，CF7 统一伤害与击杀权威。
headbotClock=0;headbotReadyAt=6;headbotTargetName="";headbotAttackOwner=null;
headbotHitCount=0;headbotAttackCount=0;headbotDeathFxPlayed=false;
headbotIdentity={};headbotCombo=null;headbotBeamShield=-1;headbotMeleeShield=-1;
headbotAlignZ=false;headbotApproachX=false;headbotMovementTarget="";
headbotTuning={shootRange:330,thrustRange:155,laneRange:24,laneStopRange:12,
    approachStopRange:290,reactionFrames:6,recoveryFrames:0,maximumTargetHeight:100,
    thrustKnockback:14,comboBeamRange:550,comboWindow:90,
    beamShieldCapacity:0.2,beamShieldStrength:0.35,beamShieldFrames:30,
    meleeLifeSteal:30,meleeShieldCapacity:0.2,meleeShieldStrength:0.35,meleeShieldFrames:180};

headbotCancelAttack=function():Void {
    if(this.headbotAttackOwner!=null)this.headbotAttackOwner.active=false;
    this.headbotAttackOwner=null;this.动作A=false;
    if(this.headbotBeamShield>=0){
        _root.护盾函数.移除护盾(this,this.headbotBeamShield);this.headbotBeamShield=-1;
    }
    if(!(this.hp>0) && this.headbotMeleeShield>=0){
        _root.护盾函数.移除护盾(this,this.headbotMeleeShield);this.headbotMeleeShield=-1;
    }
};

// 近战真实命中所得的护盾可跨越受击和收招；重复命中只刷新这一层。
headbotRewardMelee=function():Void {
    if(!(this.hp>0))return;
    var tune:Object=this.headbotTuning;
    if(this.headbotMeleeShield>=0)_root.护盾函数.移除护盾(this,this.headbotMeleeShield);
    this.headbotMeleeShield=_root.护盾函数.添加临时护盾(this,this.hp满血值*tune.meleeShieldCapacity,
        Math.max(1,this.空手攻击力*tune.meleeShieldStrength),tune.meleeShieldFrames,"机械近战盾",null);
};

状态改变=function(next:String):Void {
    if(this.hp<=0 && next!="消失")next="血腥死";
    if(next=="击倒" || next=="倒地" || next=="被投" || next=="空手跳")next="被击";
    if(this.状态==next)return;
    this.headbotCancelAttack();
    this.浮空=false;this.倒地=false;this.垂直速度=0;
    if(!isNaN(this.Z轴坐标))this._y=this.Z轴坐标;
    this.状态=next;this.gotoAndStop(next);
};

headbotBeginAttack=function(body:MovieClip,action:String):Void {
    this.headbotCancelAttack();
    var state:String=action=="thrust"?"近战":"空手攻击";
    if(!(this.hp>0) || this.状态!=state){body.stop();return;}
    var token:Object={};body.headbotToken=token;
    this.headbotAttackOwner={token:token,active:true,state:state,action:action,spec:this.headbotActions[action],lastHitFrame:0};
    if(action=="beam"){
        var tune:Object=this.headbotTuning;
        this.headbotBeamShield=_root.护盾函数.添加临时护盾(this,this.hp满血值*tune.beamShieldCapacity,
            Math.max(1,this.空手攻击力*tune.beamShieldStrength),tune.beamShieldFrames,"机械射击盾",null);
        this.headbotCombo=null;
    }
    this.headbotAttackCount++;this.headbotClearMovement();
};

headbotCanAct=function(body:MovieClip):Boolean {
    var owner:Object=this.headbotAttackOwner;
    return !_root.暂停 && this.hp>0 && !this.硬直中 && owner!=null && owner.active
        && body===this.man && body.headbotToken===owner.token && this.状态==owner.state;
};

headbotContactDue=function(frame:Number):Boolean {
    var frames:Array=this.headbotAttackOwner.spec.hits;
    for(var i:Number=0;i<frames.length;i++)if(frames[i]==frame)return true;
    return false;
};

headbotStrike=function(body:MovieClip,point:MovieClip,multiplier:Number):Void {
    if(!this.headbotCanAct(body) || point.area==null || point._parent!==body
        || point.headbotToken!==body.headbotToken || point.headbotHitFrame!=body._currentframe)return;
    var owner:Object=this.headbotAttackOwner;
    var frame:Number=body._currentframe;
    if(!this.headbotContactDue(frame))return;
    if(owner.lastHitFrame>=frame)return;
    owner.lastHitFrame=body._currentframe;
    var p:Object={x:point._x,y:point._y};body.localToGlobal(p);_root.gameworld.globalToLocal(p);
    this.headbotHitCount++;
    // 光束保留原来的两次瞬时接触，按定位走波属性；伸缩底盘保持物理。
    var bullet:Object={声音:"",霰弹值:1,子弹散射度:0,发射效果:"",
        子弹种类:"近战子弹",子弹威力:this.空手攻击力*owner.spec.power,子弹速度:0,
        Z轴攻击范围:24,击中地图效果:"",发射者:this._name,shootX:p.x,shootY:p.y,
        shootZ:this.Z轴坐标,击倒率:10,击中后子弹的效果:"空手攻击火花",
        水平击退速度:owner.action=="thrust"?this.headbotTuning.thrustKnockback:3,
        垂直击退速度:0,区域定位area:point.area,
        伤害类型:owner.action=="beam"?"魔法":"物理",
        魔法伤害属性:owner.action=="beam"?"波":undefined};
    if(owner.action=="thrust"){
        bullet.吸血=this.headbotTuning.meleeLifeSteal;
        bullet.headbotShooterIdentity=this.headbotIdentity;
        bullet.击中时触发函数=function():Void {
            if(this.headbotComboSpent===true)return;
            this.headbotComboSpent=true;
            var shooter:MovieClip=_root.gameworld[this.发射者],target:MovieClip=this.hitTarget;
            if(!(shooter.hp>0) || shooter.headbotIdentity!==this.headbotShooterIdentity
                || target._parent!==shooter._parent)return;
            shooter.headbotRewardMelee();
            if(!(target.hp>0))return;
            if(target.__headbotActionIdentity==undefined)target.__headbotActionIdentity={};
            shooter.headbotCombo={target:target._name,identity:target.__headbotActionIdentity,
                expires:shooter.headbotClock+shooter.headbotTuning.comboWindow};
        };
    }
    _root.子弹区域shoot传递(bullet);
};

headbotComboReady=function(target:MovieClip,dx:Number,dz:Number,height:Number):Boolean {
    var combo:Object=this.headbotCombo;
    if(combo==null)return false;
    if(!(target.hp>0) || target._parent!==this._parent || target._name!=combo.target
        || target.__headbotActionIdentity!==combo.identity || this.headbotClock>combo.expires){
        this.headbotCombo=null;return false;
    }
    return dx>this.headbotTuning.thrustRange && dx<=this.headbotTuning.comboBeamRange
        && dz<=this.headbotTuning.laneRange && height<=this.headbotTuning.maximumTargetHeight
        && this.headbotClock>=this.headbotReadyAt;
};

headbotFinishAttack=function(body:MovieClip):Void {
    if(!this.headbotCanAct(body))return;
    this.headbotCancelAttack();this.headbotReadyAt=this.headbotClock+this.headbotTuning.recoveryFrames;
    this.动画完毕();
};

headbotDeathFx=function():Void {
    if(this.headbotDeathFxPlayed)return;
    this.headbotDeathFxPlayed=true;
    _root.效果("火花",this._x,this._y-65,this._xscale*1.4);
    _root.效果("小烟雾",this._x,this._y-65,this._xscale*1.4);
};

// 驱动放在 man 内，标准 death 清理之后仍能完成碎裂和注销；暂停不推进。
headbotBodyTick=function(body:MovieClip):Void {
    if(_root.暂停 || body!==this.man || body.headbotMode==undefined)return;
    if(body.headbotMode=="death"){
        if(!this.cf6RobotDeathTick(body))return;
        if(body._currentframe<body._totalframes)body.nextFrame();
        else this.cf6FinishCorpse(body);
        return;
    }
    if(!(this.hp>0) || this.硬直中)return;
    if(body.headbotMode=="attack"){
        if(!this.headbotCanAct(body))return;
        var owner:Object=this.headbotAttackOwner,frame:Number=body._currentframe;
        var contact:Boolean=this.headbotContactDue(frame);
        // onLoad 可在暂停期间到达；恢复后先补本帧唯一接触，再离开该帧。
        if(contact && owner.lastHitFrame<frame){
            this.headbotStrike(body,body.攻击点,owner.spec.power);
            if(owner.lastHitFrame<frame)return;
        }
    }
    if(body._currentframe==body._totalframes)body.gotoAndStop(1);
    else body.nextFrame();
};

headbotChooseAttack=function(dx:Number,dz:Number,height:Number):String {
    var tune:Object=this.headbotTuning;
    if(isNaN(dx) || isNaN(dz) || isNaN(height) || dx<0 || dz<0 || dz>tune.laneRange
        || height>tune.maximumTargetHeight || this.headbotClock<this.headbotReadyAt)return "none";
    if(dx<=tune.thrustRange && height<=55)return "thrust";
    return dx<=tune.shootRange?"beam":"none";
};

headbotTick=function():Void {
    if(_root.暂停)return;
    this.headbotClock++;
    this.浮空=false;this.倒地=false;this.垂直速度=0;
    if(!isNaN(this.Z轴坐标) && this._y!=this.Z轴坐标)this._y=this.Z轴坐标;
    if(!isNaN(this.hp) && this.hp<=0){
        this.headbotCancelAttack();
        if(!this._killed && typeof(_root.敌人函数.标准击杀)=="function")_root.敌人函数.标准击杀(this);
        else if(this.状态!="血腥死" && this.状态!="消失")this.状态改变("血腥死");
        return;
    }
    var owner:Object=this.headbotAttackOwner;
    if(owner!=null){
        if(this.状态!=owner.state || this.man.headbotToken!==owner.token)this.headbotCancelAttack();
        return;
    }
    if(!(this.hp>0) || this.硬直中)return;
    if(_root.控制目标==this._name && _root.控制目标全自动==false)return;
    if(this.状态!="空手站立" && this.状态!="空手行走" && this.状态!="空手跑")return;
    if((this.headbotClock&3)!=0)return;
    this.x轴攻击范围=0;this.y轴攻击范围=this.headbotTuning.laneRange;
    this.x轴保持距离=this.headbotTuning.approachStopRange;
    if(this.unitAI.data!=null){
        this.unitAI.data.xrange=0;this.unitAI.data.zrange=this.y轴攻击范围;
        this.unitAI.data.xdistance=this.x轴保持距离;
    }
    var target:MovieClip=_root.gameworld[this.攻击目标];
    if(!(target.hp>0) || target===this || target.area==null){this.headbotClearMovement();return;}
    var dx:Number=target._x-this._x,dz:Number=target.Z轴坐标-this.Z轴坐标;
    var height:Number=target.Z轴坐标-target._y;
    if(target.浮空高度!=undefined && !isNaN(target.浮空高度) && target.浮空高度>0)height+=target.浮空高度;
    if(this.headbotTargetName!=target._name){
        this.headbotTargetName=target._name;this.headbotReadyAt=this.headbotClock+this.headbotTuning.reactionFrames;
    }
    var action:String=this.headbotComboReady(target,Math.abs(dx),Math.abs(dz),height)?"beam":
        this.headbotChooseAttack(Math.abs(dx),Math.abs(dz),height);
    if(action=="none"){this.headbotUpdateMovement();return;}
    this.headbotClearMovement();
    if(dx<0)this.方向改变("左");else if(dx>0)this.方向改变("右");
    this.状态改变(action=="thrust"?"近战":"空手攻击");
};
headbotClearMovement=function():Void {
    this.左行=this.右行=this.上行=this.下行=false;
    this.headbotAlignZ=this.headbotApproachX=false;
};

// Generic AI retains targeting. Only this policy supplies inputs consumed by walking.
headbotUpdateMovement=function():Void {
    this.左行=this.右行=this.上行=this.下行=false;
    var target:MovieClip=_root.gameworld[this.攻击目标];
    if(!(target.hp>0) || target===this || target.area==null){this.headbotClearMovement();return;}
    var dx:Number=target._x-this._x,dz:Number=target.Z轴坐标-this.Z轴坐标;
    if(isNaN(dx) || isNaN(dz)){this.headbotClearMovement();return;}
    if(this.headbotMovementTarget!=target._name){
        this.headbotAlignZ=this.headbotApproachX=false;this.headbotMovementTarget=target._name;
    }
    var tune:Object=this.headbotTuning,ax:Number=Math.abs(dx),az:Number=Math.abs(dz);
    if(az>tune.laneRange)this.headbotAlignZ=true;
    else if(az<=tune.laneStopRange)this.headbotAlignZ=false;
    if(ax>tune.shootRange)this.headbotApproachX=true;
    else if(ax<=tune.approachStopRange)this.headbotApproachX=false;
    this.上行=this.headbotAlignZ && dz<0;this.下行=this.headbotAlignZ && dz>0;
    this.左行=this.headbotApproachX && dx<0;this.右行=this.headbotApproachX && dx>0;
};

行走=function():Void {
    if(_root.暂停)return;
    if(_root.控制目标==this._name && _root.控制目标全自动==false){
        _root.敌人函数.行走.call(this);return;
    }
    if(!(this.hp>0) || this.浮空 || this.倒地 || this.硬直中
        || this.headbotAttackOwner!=null){this.headbotClearMovement();return;}
    if(this.状态!="空手站立" && this.状态!="空手行走" && this.状态!="空手跑")return;
    // Re-evaluate at the movement consumer on every frame, after any generic AI write.
    this.headbotUpdateMovement();
    var target:MovieClip=_root.gameworld[this.攻击目标];
    var movingX:Boolean=this.左行 || this.右行,movingZ:Boolean=this.上行 || this.下行;
    var running:Boolean=movingX && Math.abs(target._x-this._x)>this.headbotTuning.shootRange;
    if(movingX){
        var direction:String=this.右行?"右":"左";this.方向改变(direction);
        var speedX:Number=running?this.跑X速度:this.行走X速度;
        this.移动(direction,Math.min(speedX,Math.max(0,Math.abs(target._x-this._x)-this.headbotTuning.approachStopRange)));
    }
    if(movingZ){
        var speedZ:Number=running?this.跑Y速度:this.行走Y速度;
        this.移动(this.下行?"下":"上",Math.min(speedZ,Math.max(0,Math.abs(target.Z轴坐标-this.Z轴坐标)-this.headbotTuning.laneStopRange)));
    }
    this.状态改变(movingX || movingZ?(running?"空手跑":"空手行走"):"空手站立");
};
