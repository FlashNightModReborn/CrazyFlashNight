// 悬浮机械单位：原稿双光束 / 四段伸缩，CF7 统一伤害与击杀权威。
headbotClock=0;headbotReadyAt=6;headbotTargetName="";headbotAttackOwner=null;
headbotHitCount=0;headbotAttackCount=0;headbotDeathFxPlayed=false;
headbotIdentity={};headbotCombo=null;headbotBeamShield=-1;headbotMeleeShield=-1;
headbotPendingBeamSubmode="";headbotPendingShield=false;headbotShieldSkillId=-1;
headbotNextShieldClock=0;headbotLastShieldHp=undefined;headbotNextAntiair=0;headbotNextRetreatBlast=0;
headbotAlignZ=false;headbotApproachX=false;headbotMovementTarget="";headbotRetreatHoldUntil=0;headbotLastRetreatDistance=0;
headbotTuning={shootRange:330,thrustRange:155,laneRange:24,laneStopRange:12,
    approachStopRange:290,reactionFrames:6,recoveryFrames:0,maximumTargetHeight:100,
    thrustKnockback:14,thrustAdvanceSpeed:6,comboBeamRange:620,comboWindow:90,
    retreatBlastRange:245,retreatBlastCooldown:70,retreatSpeed:12.5,retreatDistance:320,retreatHoldFrames:24,antiairMinHeight:56,
    antiairGroundRange:275,antiairBombardRange:480,antiairLaneRange:90,
    antiairCooldown:90,antiairShellDelay:25,
    shieldCooldown:300,shieldSkillCapacity:0.25,shieldSkillStrength:0.45,shieldSkillFrames:180,shieldTriggerLossRatio:0.35,
    beamShieldCapacity:0.2,beamShieldStrength:0.35,beamShieldFrames:30,
    meleeLifeSteal:30,meleeShieldCapacity:0.2,meleeShieldStrength:0.35,meleeShieldFrames:180};

headbotCancelAttack=function():Void {
    if(this.headbotAttackOwner!=null){
        if(this.headbotAttackOwner.ownsRigid){
            this.刚体=this.headbotAttackOwner.previousRigid;
            this.免疫击退=this.headbotAttackOwner.previousImmune;
        }
        this.headbotAttackOwner.active=false;
    }
    this.headbotAttackOwner=null;this.动作A=false;
    if(this.headbotBeamShield>=0){
        _root.护盾函数.移除护盾(this,this.headbotBeamShield);this.headbotBeamShield=-1;
    }
    if(!(this.hp>0) && this.headbotMeleeShield>=0){
        _root.护盾函数.移除护盾(this,this.headbotMeleeShield);this.headbotMeleeShield=-1;
    }
    if(!(this.hp>0) && this.headbotShieldSkillId>=0){
        _root.护盾函数.移除护盾(this,this.headbotShieldSkillId);this.headbotShieldSkillId=-1;
    }
};

headbotBeginShield=function(body:MovieClip):Void {
    if(!(this.hp>0)){body.stop();return;}
    var tune:Object=this.headbotTuning;
    if(this.headbotShieldSkillId>=0)_root.护盾函数.移除护盾(this,this.headbotShieldSkillId);
    this.headbotShieldSkillId=_root.护盾函数.添加临时护盾(this,this.hp满血值*tune.shieldSkillCapacity,
        Math.max(1,this.空手攻击力*tune.shieldSkillStrength),tune.shieldSkillFrames,"机械展开盾",null);
    this.headbotNextShieldClock=this.headbotClock+tune.shieldCooldown;
    body.headbotMode="shield";
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
    if(this.headbotLastShieldHp==undefined)this.headbotLastShieldHp=this.hp满血值;
    if(next=="被击" && this.hp>0 && (this.headbotLastShieldHp-this.hp)>=this.hp满血值*this.headbotTuning.shieldTriggerLossRatio && this.headbotClock>=this.headbotNextShieldClock){
        this.headbotLastShieldHp=this.hp;this.headbotPendingShield=true;
    }
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
    this.headbotAttackOwner={token:token,active:true,state:state,action:action,spec:this.headbotActions[action],lastHitFrame:0,
        previousRigid:this.刚体===true,previousImmune:this.免疫击退===true,ownsRigid:true,retreatSign:this.方向=="左"?1:-1,retreatMoved:0};
    this.刚体=true;this.免疫击退=true;
    if(action=="beam" || action=="antiair" || action=="retreat_blast"){
        var tune:Object=this.headbotTuning;
        if(action=="beam"){
            this.headbotBeamShield=_root.护盾函数.添加临时护盾(this,this.hp满血值*tune.beamShieldCapacity,
                Math.max(1,this.空手攻击力*tune.beamShieldStrength),tune.beamShieldFrames,"机械射击盾",null);
        }
        this.headbotCombo=null;
        if(action=="antiair")this.headbotNextAntiair=this.headbotClock+tune.antiairCooldown;
        if(action=="retreat_blast")this.headbotNextRetreatBlast=this.headbotClock+tune.retreatBlastCooldown;
    }
    this.headbotAttackCount++;this.headbotClearMovement();
};

headbotSpawnFallingShell=function(shellIndex:Number,power:Number):Void {
    var world:MovieClip=_root.gameworld;
    if(world==null)return;
    var dir:Number=this.方向=="左"?-1:1;
    var target:MovieClip=world[this.攻击目标];
    var hasTarget:Boolean=target!=null && target.hp>0 && target!==this && target.area!=null && !isNaN(target._x);
    var baseX:Number=hasTarget?target._x:(this._x+dir*230);
    var baseZ:Number=(hasTarget && !isNaN(target.Z轴坐标))?target.Z轴坐标:this.Z轴坐标;
    var strikeX:Number=baseX+(shellIndex>0?dir*55:0);
    var strikeZ:Number=baseZ;
    var depth:Number=world.getNextHighestDepth();
    var clip:MovieClip=world.createEmptyMovieClip("cf6HeadbotShell"+depth+"_"+this.headbotClock,depth);
    clip._x=strikeX;clip._y=strikeZ;
    var area:MovieClip=clip.createEmptyMovieClip("area",1);
    area.beginFill(0,0);area.moveTo(-90,-110);area.lineTo(90,-110);area.lineTo(90,10);area.lineTo(-90,10);area.lineTo(-90,-110);area.endFill();
    area._visible=false;
    var fxDepth:Number=1000+((this.headbotClock*2+(shellIndex>0?1:0))&511);
    var fx:MovieClip=this.cf6BombTemplate!=null?this.cf6BombTemplate.duplicateMovieClip("cf6ShellFx_"+fxDepth,fxDepth):null;
    if(fx!=null){fx._visible=true;fx.gotoAndStop(1);}
    clip.fx=fx;
    clip.age=0;
    clip.delayFrames=this.headbotTuning.antiairShellDelay+(shellIndex>0?4:0);
    clip.shooterName=this._name;
    clip.shooterIdentity=this.headbotIdentity;
    clip.bulletPower=this.空手攻击力*power;
    clip.strikeX=strikeX;
    clip.strikeZ=strikeZ;
    clip.onUnload=function():Void {
        if(this.fx!=null){this.fx.removeMovieClip();this.fx=null;}
    };
    clip.onEnterFrame=function():Void {
        if(_root.暂停)return;
        this.age++;
        var d:Number=this.delayFrames;
        var shooter:MovieClip=_root.gameworld[this.shooterName];
        var shooterValid:Boolean=shooter!=null && shooter._parent===_root.gameworld && shooter.headbotIdentity===this.shooterIdentity;
        if(this.fx!=null){
            if(!shooterValid){
                this.fx.removeMovieClip();this.fx=null;
            }else{
                var sx:Number=shooter._xscale/100,sy:Number=shooter._yscale/100;
                if(!sx)sx=1;if(!sy)sy=1;
                this.fx._x=(this.strikeX-shooter._x)/sx;
                this.fx._y=(this.strikeZ-shooter._y)/sy;
                this.fx._xscale=100/sx;
                this.fx._yscale=100/sy;
            }
        }
        if(this.age<d){
            if(this.fx!=null){
                if(this.age<d-12)this.fx.gotoAndStop(2+((this.age-1)%12));
                else this.fx.gotoAndStop(14+(this.age-(d-12)));
            }
        }else if(this.age==d){
            if(this.fx!=null)this.fx.gotoAndStop(26);
            if(shooterValid && shooter.hp>0){
                _root.效果("火花",this.strikeX,this.strikeZ,120);
                var bullet:Object={声音:"",霰弹值:1,子弹散射度:0,发射效果:"",
                    子弹种类:"近战子弹",子弹威力:this.bulletPower,子弹速度:0,
                    Z轴攻击范围:42,击中地图效果:"",发射者:this.shooterName,
                    shootX:this.strikeX,shootY:this.strikeZ,shootZ:this.strikeZ,
                    击倒率:10,击中后子弹的效果:"空手攻击火花",
                    水平击退速度:6,垂直击退速度:-4,区域定位area:this.area,
                    伤害类型:"魔法",魔法伤害属性:"波",
                    headbotShooterIdentity:this.shooterIdentity,cf6FallingShell:true};
                bullet.击中时触发函数=function():Void {
                    if(this.headbotShellRewarded===true)return;
                    this.headbotShellRewarded=true;
                    var s:MovieClip=_root.gameworld[this.发射者],t:MovieClip=this.hitTarget;
                    if(!(s.hp>0) || s.headbotIdentity!==this.headbotShooterIdentity)return;
                    s.headbotReadyAt=0;
                    if(t!=null && t.hp>0 && t._parent===s._parent){
                        if(t.__headbotActionIdentity==undefined)t.__headbotActionIdentity={};
                        s.headbotCombo={target:t._name,identity:t.__headbotActionIdentity,
                            expires:s.headbotClock+s.headbotTuning.comboWindow};
                    }
                };
                _root.子弹区域shoot传递(bullet);
            }
        }else if(this.age<=d+9){
            if(this.fx!=null)this.fx.gotoAndStop(26+(this.age-d));
        }else{
            if(this.fx!=null){this.fx.removeMovieClip();this.fx=null;}
            this.removeMovieClip();
        }
    };
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
    // 光束 / 对空射击 / 后撤爆破走波属性；伸缩底盘保持物理。
    var isMagic:Boolean=owner.action!="thrust";
    var bullet:Object={声音:"",霰弹值:1,子弹散射度:0,发射效果:"",
        子弹种类:"近战子弹",子弹威力:this.空手攻击力*owner.spec.power,子弹速度:0,
        Z轴攻击范围:24,击中地图效果:"",发射者:this._name,shootX:p.x,shootY:p.y,
        shootZ:this.Z轴坐标,击倒率:10,击中后子弹的效果:"空手攻击火花",
        水平击退速度:owner.action=="thrust"?this.headbotTuning.thrustKnockback:(owner.action=="retreat_blast"?12:3),
        垂直击退速度:owner.action=="antiair"?-6:0,区域定位area:point.area,
        伤害类型:isMagic?"魔法":"物理",
        魔法伤害属性:isMagic?"波":undefined};
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
    }else if(owner.action=="retreat_blast" || owner.action=="antiair"){
        bullet.headbotShooterIdentity=this.headbotIdentity;
        bullet.headbotAction=owner.action;
        bullet.击中时触发函数=function():Void {
            if(this.headbotBeamRewardSpent===true)return;
            this.headbotBeamRewardSpent=true;
            var shooter:MovieClip=_root.gameworld[this.发射者],target:MovieClip=this.hitTarget;
            if(!(shooter.hp>0) || shooter.headbotIdentity!==this.headbotShooterIdentity)return;
            shooter.headbotReadyAt=0;
            if(target!=null && target.hp>0 && target._parent===shooter._parent){
                if(target.__headbotActionIdentity==undefined)target.__headbotActionIdentity={};
                shooter.headbotCombo={target:target._name,identity:target.__headbotActionIdentity,
                    expires:shooter.headbotClock+shooter.headbotTuning.comboWindow};
            }
        };
    }
    _root.子弹区域shoot传递(bullet);
    if(owner.action=="antiair"){
        this.headbotSpawnFallingShell(frame==49?1:0,owner.spec.power);
    }
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
    if(this.headbotAttackOwner.action=="retreat_blast"){
        this.headbotLastRetreatDistance=this.headbotAttackOwner.retreatMoved;
        this.headbotRetreatHoldUntil=this.headbotClock+this.headbotTuning.retreatHoldFrames;
    }
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
headbotRetreatStep=function(owner:Object):Void {
    var remaining:Number=Math.min(this.headbotTuning.retreatSpeed,this.headbotTuning.retreatDistance-owner.retreatMoved);
    // Mover owns collision/depth/AABB. Small steps keep thin walls authoritative.
    while(remaining>0.01){
        var step:Number=Math.min(6,remaining),before:Number=this._x;
        this.移动(owner.retreatSign<0?"左":"右",step);
        var moved:Number=Math.abs(this._x-before);
        owner.retreatMoved+=moved;remaining-=step;
        if(moved<step-0.1)break;
    }
};
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
        if(owner.action=="thrust" && frame>=2 && frame<=12){
            var thrustTarget:MovieClip=_root.gameworld[this.攻击目标];
            if(thrustTarget!=null && thrustTarget.hp>0 && !isNaN(thrustTarget._x)){
                var tdx:Number=thrustTarget._x-this._x;
                if(Math.abs(tdx)>85 && ((this.方向=="右" && tdx>0) || (this.方向=="左" && tdx<0))){
                    this.移动(this.方向,Math.min(this.headbotTuning.thrustAdvanceSpeed,Math.abs(tdx)-85));
                }
            }
        }
        if(owner.action=="retreat_blast" && frame>=83 && frame<=108)this.headbotRetreatStep(owner);
        if((owner.action=="beam" && frame>=30)
            || (owner.action=="antiair" && frame>=70)
            || (owner.action=="retreat_blast" && frame>=109)){
            this.headbotFinishAttack(body);return;
        }
    }else if(body.headbotMode=="hit"){
        if(body._currentframe>=25){
            this.动画完毕();return;
        }
    }else if(body.headbotMode=="shield"){
        if(body._currentframe>=88){
            this.动画完毕();return;
        }
    }
    if(body._currentframe==body._totalframes)body.gotoAndStop(1);
    else body.nextFrame();
};

headbotSelectBeamSubmode=function(dx:Number,height:Number):String {
    var tune:Object=this.headbotTuning;
    if(height>=tune.antiairMinHeight)return this.headbotClock>=this.headbotNextAntiair?"antiair":"beam";
    if(dx<=tune.retreatBlastRange && this.headbotClock>=this.headbotNextRetreatBlast)return "retreat_blast";
    if(dx>=tune.antiairGroundRange && this.headbotClock>=this.headbotNextAntiair)return "antiair";
    return "beam";
};

headbotBombardReady=function(dx:Number,dz:Number,height:Number):Boolean {
    var tune:Object=this.headbotTuning;
    if(isNaN(dx) || isNaN(dz) || isNaN(height) || dx<tune.antiairGroundRange || dx>tune.antiairBombardRange
        || dz<0 || dz>tune.antiairLaneRange || height>tune.maximumTargetHeight)return false;
    return this.headbotClock>=this.headbotReadyAt && this.headbotClock>=this.headbotNextAntiair;
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
    var absDx:Number=Math.abs(dx),absDz:Number=Math.abs(dz);
    var comboReady:Boolean=this.headbotComboReady(target,absDx,absDz,height);
    var action:String=comboReady?"beam":
        this.headbotChooseAttack(absDx,absDz,height);
    if(action=="thrust" && absDx<=this.headbotTuning.retreatBlastRange && this.headbotClock>=this.headbotNextRetreatBlast){
        action="beam";
    }
    var bombard:Boolean=false;
    if(action=="none" && this.headbotBombardReady(absDx,absDz,height)){
        action="beam";bombard=true;
    }
    if(action=="none"){this.headbotUpdateMovement();return;}
    this.headbotClearMovement();
    if(dx<0)this.方向改变("左");else if(dx>0)this.方向改变("右");
    if(action=="beam"){
        // 真实命中所得的光束连携不再被普通距离选招改写成延迟轰炸。
        var submode:String=comboReady?"beam":bombard?"antiair":this.headbotSelectBeamSubmode(absDx,height);
        this.headbotPendingBeamSubmode=submode=="beam"?"":submode;
    }
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
    if(this.headbotClock<this.headbotRetreatHoldUntil)this.headbotApproachX=false;
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
