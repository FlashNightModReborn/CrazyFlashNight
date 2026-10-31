// 起手到发力段同时持有刚体与抗位移；收招恢复原状态，不减免伤害。
// CF6 重劈和横扫把敌人推入波属性光束射程；伤害与位移使用 CF7 权威。
bladebotClock=0;
bladebotReadyAt=6;
bladebotNextSweep=0;
bladebotNextDash=0;
bladebotNextBeam=0;
bladebotSpinShield=-1;
bladebotCombo=null;
bladebotComboCount=0;
bladebotTargetName="";
bladebotAttackOwner=null;
bladebotAttackCount=0;
bladebotHitCount=0;
bladebotDeathFxPlayed=false;
bladebotIdentity={};
bladebotTuning={cleaveRange:245,sweepRange:205,dashMinRange:250,dashRange:380,laneRange:30,keepDistance:85,
    reactionFrames:6,recoveryFrames:0,sweepCooldown:36,dashCooldown:45,dashSpeed:14,
    spinShieldCapacity:0.30,spinShieldStrength:3.0,maximumTargetHeight:150,airSweepRange:190,cleaveTargetHeight:80,
    beamMinRange:250,beamRange:600,beamCooldown:45,comboWindow:45};

bladebotState=function(action:String):String {
    return action=="beam"?"激光束":action=="sweep"?"近战":action=="dash"?"旋刃冲刺":"空手攻击";
};

bladebotCancelAttack=function():Void {
    if(this.bladebotSpinShield>=0 && _root.护盾函数!=null && typeof _root.护盾函数.移除护盾=="function") {
        _root.护盾函数.移除护盾(this,this.bladebotSpinShield);
    }
    this.bladebotSpinShield=-1;
    var owner:Object=this.bladebotAttackOwner;
    if(owner==null) return;
    owner.active=false;
    if(owner.ownsRigid) {this.刚体=owner.previousRigid;this.免疫击退=owner.previousImmune;}
    this.bladebotAttackOwner=null;
};

bladebotBeginAttack=function(body:MovieClip,action:String):Void {
    this.bladebotCancelAttack();
    this.bladebotCombo=null;
    if(!(this.hp>0) || this.状态!=this.bladebotState(action)) {body.stop();return;}
    var token:Object={}; body.bladebotToken=token;
    this.bladebotAttackOwner={token:token,action:action,active:true,
        previousRigid:this.刚体===true,previousImmune:this.免疫击退===true,ownsRigid:true,lastHitFrame:0,target:this.攻击目标};
    var target:MovieClip=_root.gameworld[this.攻击目标];
    if(target.hp>0){
        if(target.__bladebotComboIdentity==undefined)target.__bladebotComboIdentity={};
        this.bladebotAttackOwner.targetIdentity=target.__bladebotComboIdentity;
    }
    if(action=="beam")this.bladebotLockBeamAim(body,target);
    this.刚体=true;this.免疫击退=true;
    this.bladebotAttackCount++;
    if(action=="sweep") this.bladebotNextSweep=this.bladebotClock+this.bladebotTuning.sweepCooldown;
    if(action=="dash") this.bladebotNextDash=this.bladebotClock+this.bladebotTuning.dashCooldown;
    if(action=="beam") {this.bladebotNextBeam=this.bladebotClock+this.bladebotTuning.beamCooldown;this.bladebotCombo=null;}
    if((action=="sweep" || action=="dash") && _root.护盾函数!=null && typeof _root.护盾函数.添加临时护盾=="function") {
        var shieldCap:Number=Math.max(300,Math.floor(this.hp满血值*this.bladebotTuning.spinShieldCapacity));
        var shieldStr:Number=Math.max(220,Math.floor(this.空手攻击力*this.bladebotTuning.spinShieldStrength));
        this.bladebotSpinShield=_root.护盾函数.添加临时护盾(this,shieldCap,shieldStr,action=="sweep"?78:50,"大刀旋刃护盾",null);
    }
};

// 起手锁定实际受击框中心；光束图形与接触框共用同一眼部支点和旋转。
bladebotLockBeamAim=function(body:MovieClip,target:MovieClip):Void {
    var owner:Object=this.bladebotAttackOwner;owner.beamAngle=0;
    if(!(target.hp>0) || target.area==null)return;
    var bounds:Object=target.area.getBounds(_root.gameworld);
    if(!(bounds.xMax>bounds.xMin) || !(bounds.yMax>bounds.yMin))return;
    var aim:Object={x:(bounds.xMin+bounds.xMax)/2,
        y:(bounds.yMin+bounds.yMax)/2+this.Z轴坐标-target.Z轴坐标};
    _root.gameworld.localToGlobal(aim);body.globalToLocal(aim);
    if(!(aim.x>7.1) || isNaN(aim.y))return;
    owner.beamAngle=Math.max(-25,Math.min(25,Math.atan2(aim.y+31.9,aim.x-7.1)*180/Math.PI));
};
bladebotAimPart=function(part:MovieClip):Void {
    var owner:Object=this.bladebotAttackOwner;
    if(owner==null || owner.action!="beam" || part._parent!==this.man || part.bladebotAimToken===owner.token)return;
    part.bladebotAimToken=owner.token;
    var angle:Number=owner.beamAngle*Math.PI/180,c:Number=Math.cos(angle),s:Number=Math.sin(angle);
    var m:flash.geom.Matrix=part.transform.matrix,a:Number=m.a,b:Number=m.b,cc:Number=m.c,d:Number=m.d;
    var x:Number=m.tx-7.1,y:Number=m.ty+31.9;
    m.a=c*a-s*b;m.b=s*a+c*b;m.c=c*cc-s*d;m.d=s*cc+c*d;
    m.tx=7.1+c*x-s*y;m.ty=-31.9+s*x+c*y;part.transform.matrix=m;
};

bladebotCanAct=function(body:MovieClip):Boolean {
    var owner:Object=this.bladebotAttackOwner;
    return !_root.暂停 && this.hp>0 && !this.硬直中 && owner!=null && owner.active
        && body===this.man && body.bladebotToken===owner.token
        && this.状态==this.bladebotState(owner.action);
};

bladebotFinishAttack=function(body:MovieClip):Void {
    var owner:Object=this.bladebotAttackOwner;
    if(owner==null || body!==this.man || owner.token!==body.bladebotToken) return;
    if((owner.action=="cleave" || owner.action=="sweep" || owner.action=="dash") && owner.lastHitFrame>0 && owner.targetIdentity!=undefined){
        this.bladebotCombo={target:owner.target,identity:owner.targetIdentity,
            expires:this.bladebotClock+this.bladebotTuning.comboWindow};
    }
    this.bladebotCancelAttack();
    this.bladebotReadyAt=this.bladebotClock+this.bladebotTuning.recoveryFrames;
    this.动画完毕();
};

bladebotAdvance=function(body:MovieClip,amount:Number):Void {
    if(!this.bladebotCanAct(body)) return;
    var target:MovieClip=_root.gameworld[this.bladebotAttackOwner.target];
    if(!(target.hp>0)) return;
    var dx:Number=target._x-this._x;
    var dz:Number=target.Z轴坐标-this.Z轴坐标;
    if(isNaN(dx) || isNaN(dz) || Math.abs(dz)>90) return;
    if(Math.abs(dz)>6) {
        // 纵深同样通过正式碰撞、深度与受击框更新出口。
        this.移动(dz<0?"上":"下",Math.min(2.5,Math.abs(dz)));
    }
    if((this.方向=="右" && dx>95) || (this.方向=="左" && dx< -95)) {
        this.移动(this.方向,Math.min(amount,Math.abs(dx)-95));
    }
};

bladebotDashAdvance=function(body:MovieClip,amount:Number):Void {
    if(!this.bladebotCanAct(body)) return;
    var owner:Object=this.bladebotAttackOwner;
    var target:MovieClip=_root.gameworld[owner.target];
    if(!(target.hp>0)) return;
    var dx:Number=target._x-this._x;
    var dz:Number=target.Z轴坐标-this.Z轴坐标;
    if(isNaN(dx) || isNaN(dz) || Math.abs(dz)>110) return;
    if(Math.abs(dz)>6) {
        this.移动(dz<0?"上":"下",Math.min(3.5,Math.abs(dz)));
    }
    if(owner.dashTurned!==true && ((this.方向=="右" && dx< -55) || (this.方向=="左" && dx>55))) {
        owner.dashTurned=true;
        this.方向改变(dx<0?"左":"右");
    }
    if((this.方向=="右" && dx> -45) || (this.方向=="左" && dx<45)) {
        this.移动(this.方向,amount);
    }
};

bladebotContactDue=function(action:String,frame:Number):Boolean {
    if(action=="beam") return frame==14;
    if(action=="cleave") return frame==20 || frame==22;
    if(action=="dash") return frame>=4 && frame<=49 && ((frame-4)%3)==0;
    return (frame>=19 && frame<=73 && ((frame-19)%3)==0) || frame==75;
};

bladebotStrike=function(body:MovieClip,point:MovieClip,multiplier:Number):Void {
    this.bladebotAimPart(point);
    if(!this.bladebotCanAct(body) || point.area==null || point._parent!==body
        || point.bladebotToken!==body.bladebotToken || point.bladebotHitFrame!=body._currentframe) return;
    var owner:Object=this.bladebotAttackOwner;
    var frame:Number=body._currentframe;
    if(!this.bladebotContactDue(owner.action,frame)) return;
    if(owner.lastHitFrame>=frame) return;
    owner.lastHitFrame=body._currentframe;
    var p:Object={x:point._x,y:point._y};
    body.localToGlobal(p); _root.gameworld.globalToLocal(p);
    var heavy:Boolean=owner.action=="cleave";
    var beam:Boolean=owner.action=="beam";
    var dash:Boolean=owner.action=="dash";
    this.bladebotHitCount++;
    var bullet:Object={声音:"",霰弹值:1,子弹散射度:0,发射效果:"",
        子弹种类:"近战子弹",子弹威力:this.空手攻击力*multiplier,子弹速度:0,
        Z轴攻击范围:30,击中地图效果:"",发射者:this._name,shootX:p.x,shootY:p.y,
        shootZ:this.Z轴坐标,击倒率:heavy?3:10,击中后子弹的效果:"空手攻击火花",
        水平击退速度:heavy?29:beam?2:dash?(frame>=49?26:4):3,垂直击退速度:heavy || beam || dash?0:2,区域定位area:point.area,
        伤害类型:beam?"魔法":"物理",魔法伤害属性:beam?"波":undefined,
        bladebotShooterIdentity:this.bladebotIdentity,bladebotAction:owner.action,bladebotHitFrame:frame};
    bullet.击中时触发函数=function():Void {
        if(this.bladebotStrikeRewarded===true) return;
        this.bladebotStrikeRewarded=true;
        var shooter:MovieClip=_root.gameworld[this.发射者];
        var target:MovieClip=this.hitTarget;
        if(!(shooter.hp>0) || shooter.bladebotIdentity!==this.bladebotShooterIdentity) return;
        if(target!=null && target.hp>0 && target.area!=null) {
            if((this.bladebotAction=="cleave" && this.bladebotHitFrame>=22)
                || (this.bladebotAction=="sweep" && this.bladebotHitFrame>=75)
                || (this.bladebotAction=="dash" && this.bladebotHitFrame>=49)) {
                if(target.__bladebotComboIdentity==undefined) target.__bladebotComboIdentity={};
                shooter.bladebotCombo={target:target._name,identity:target.__bladebotComboIdentity,
                    expires:shooter.bladebotClock+shooter.bladebotTuning.comboWindow};
                shooter.bladebotNextBeam=0;
                shooter.bladebotReadyAt=0;
            }
        }
    };
    _root.子弹区域shoot传递(bullet);
};

// 暂停期间 onLoad 到达时保留本帧，恢复后只补一次实际接触。
bladebotBodyTick=function(body:MovieClip):Void {
    if(body===this.man && body.bladebotMode=="death"){
        if(this.cf6RobotDeathTick(body) && body._currentframe<body._totalframes)body.nextFrame();
        return;
    }
    if(!this.bladebotCanAct(body))return;
    var owner:Object=this.bladebotAttackOwner,frame:Number=body._currentframe;
    var due:Boolean=this.bladebotContactDue(owner.action,frame);
    if(due && owner.lastHitFrame<frame){
        this.bladebotStrike(body,body.攻击点,owner.action=="cleave"?2.4:(owner.action=="dash"?0.85:1));
        if(owner.lastHitFrame<frame)return;
    }
    if(owner.action=="dash" && frame>=2 && frame<=48){
        this.bladebotDashAdvance(body,this.bladebotTuning.dashSpeed);
    }
    if(frame<body._totalframes)body.nextFrame();
};

bladebotComboReady=function(target:MovieClip,dx:Number,dz:Number,height:Number):Boolean {
    var combo:Object=this.bladebotCombo,tune:Object=this.bladebotTuning;
    if(combo==null || isNaN(dx) || isNaN(dz) || isNaN(height))return false;
    if(this.bladebotClock>combo.expires || !(target.hp>0) || target._parent!==this._parent
        || target._name!=combo.target || target.__bladebotComboIdentity!==combo.identity){this.bladebotCombo=null;return false;}
    return dx>=tune.beamMinRange && dx<=tune.beamRange && dz<=tune.laneRange && height<=tune.cleaveTargetHeight
        && this.bladebotClock>=this.bladebotNextBeam && this.bladebotClock>=this.bladebotReadyAt;
};

bladebotChooseAttack=function(dx:Number,dz:Number,height:Number):String {
    var tune:Object=this.bladebotTuning;
    if(isNaN(dx) || isNaN(dz) || isNaN(height) || dx<0 || dz<0 || dz>tune.laneRange
        || height>tune.maximumTargetHeight || this.bladebotClock<this.bladebotReadyAt) return "none";
    if(height>tune.cleaveTargetHeight) {
        return dx<=tune.airSweepRange && this.bladebotClock>=this.bladebotNextSweep?"sweep":"none";
    }
    if(dx<=tune.sweepRange && this.bladebotClock>=this.bladebotNextSweep) return "sweep";
    if(dx<=tune.cleaveRange) return "cleave";
    if(dx>=tune.dashMinRange && dx<=tune.dashRange && height<=tune.cleaveTargetHeight
        && this.bladebotClock>=this.bladebotNextDash) return "dash";
    if(dx>=tune.beamMinRange && dx<=tune.beamRange && height<=tune.cleaveTargetHeight
        && this.bladebotClock>=this.bladebotNextBeam)return "beam";
    return "none";
};

bladebotDeathFx=function():Void {
    if(this.bladebotDeathFxPlayed) return;
    this.bladebotDeathFxPlayed=true;
    // 小火花先行，私有矢量爆裂和一次性亡语另由死亡时钟管理。
    _root.效果("火花",this._x,this._y-65,this._xscale*1.4);
    _root.效果("小烟雾",this._x,this._y-65,this._xscale*1.4);
};

bladebotTick=function():Void {
    if(_root.暂停) return;
    this.bladebotClock++;
    if(!isNaN(this.hp) && this.hp<=0) {
        this.bladebotCancelAttack();
        if(this.状态!="血腥死" && this.状态!="消失") this.状态改变("血腥死");
        return;
    }
    var owner:Object=this.bladebotAttackOwner;
    if(owner!=null) {
        var state:String=this.bladebotState(owner.action);
        if(this.状态!=state || this.man.bladebotToken!==owner.token) this.bladebotCancelAttack();
        else {
            var frame:Number=this.man._currentframe;
            var active:Boolean=owner.action=="sweep"?(frame>=1 && frame<=75):owner.action=="dash"?(frame>=1 && frame<=49):owner.action=="beam"?(frame>=1 && frame<=28):(frame>=1 && frame<=38);
            if(active && !owner.ownsRigid) {
                owner.previousRigid=this.刚体===true;owner.previousImmune=this.免疫击退===true;
                owner.ownsRigid=true;this.刚体=true;this.免疫击退=true;
            } else if(!active && owner.ownsRigid) {
                this.刚体=owner.previousRigid;this.免疫击退=owner.previousImmune;owner.ownsRigid=false;
            }
        }
    }
    if(!(this.hp>0) || this.倒地 || this.浮空 || this.硬直中) return;
    if(_root.控制目标==this._name && _root.控制目标全自动==false) return;
    if(this.状态!="空手站立" && this.状态!="空手行走" && this.状态!="空手跑") return;
    if((this.bladebotClock&3)!=0) return;
    this.x轴攻击范围=0;this.y轴攻击范围=this.bladebotTuning.laneRange;
    this.x轴保持距离=this.bladebotTuning.keepDistance;
    if(this.unitAI.data!=null) {
        this.unitAI.data.xrange=0;this.unitAI.data.zrange=this.y轴攻击范围;
        this.unitAI.data.xdistance=this.x轴保持距离;
    }
    var target:MovieClip=_root.gameworld[this.攻击目标];
    if(!(target.hp>0) || target==this || target.area==null) return;
    var dx:Number=target._x-this._x,dz:Number=target.Z轴坐标-this.Z轴坐标;
    var height:Number=target.Z轴坐标-target._y;
    // 部分原生动作只移动受击区域，使用既有的附加浮空高度合同。
    if(target.浮空高度!=undefined && !isNaN(target.浮空高度) && target.浮空高度>0) height+=target.浮空高度;
    if(isNaN(dx) || isNaN(dz) || isNaN(height)) return;
    if(this.bladebotTargetName!=target._name) {
        this.bladebotTargetName=target._name;
        this.bladebotReadyAt=this.bladebotClock+this.bladebotTuning.reactionFrames;
    }
    var action:String;
    if(this.bladebotComboReady(target,Math.abs(dx),Math.abs(dz),height)) {action="beam";this.bladebotComboCount++;}
    else action=this.bladebotChooseAttack(Math.abs(dx),Math.abs(dz),height);
    if(action=="none") {
        this.上行=dz< -6;this.下行=dz>6;
        this.左行=dx< -this.bladebotTuning.keepDistance;this.右行=dx>this.bladebotTuning.keepDistance;
        if(Math.abs(dx)>260 && this.状态!="空手跑") this.状态改变("空手跑");
        return;
    }
    this.左行=this.右行=this.上行=this.下行=false;
    if(dx<0) this.方向改变("左"); else if(dx>0) this.方向改变("右");
    this.状态改变(this.bladebotState(action));
};
