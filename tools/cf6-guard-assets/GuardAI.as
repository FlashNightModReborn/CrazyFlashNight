// 固定散弹枪使用怪物空手面板；通用 AI 负责索敌，本单位负责移动与动作时序。
guardClock=0;guardReadyAt=6;guardNextMelee=0;guardTargetName="";guardAttackOwner=null;
guardShotCount=0;guardMeleeCount=0;guardAttackCount=0;guardInvalidMuzzleCount=0;
guardIdentity={};guardCombo=null;guardPendingFollowup=null;guardFollowupCount=0;
guardAlignZ=false;guardApproachX=false;guardMovementTarget="";
guardTuning={shootRange:380,meleeRange:85,meleeCooldown:75,laneRange:24,laneStopRange:12,approachStopRange:340,
    reactionFrames:6,recoveryFrames:4,maximumTargetHeight:65,pellets:3,followupRange:620,followupWindow:90};

guardClearMovement=function():Void {
    this.左行=this.右行=this.上行=this.下行=false;
    this.guardAlignZ=this.guardApproachX=false;
};

// Generic AI retains targeting. Only this policy supplies inputs consumed by walking.
guardUpdateMovement=function():Void {
    this.左行=this.右行=this.上行=this.下行=false;
    var target:MovieClip=_root.gameworld[this.攻击目标];
    if(!(target.hp>0) || target===this || target.area==null){this.guardClearMovement();return;}
    var dx:Number=target._x-this._x,dz:Number=target.Z轴坐标-this.Z轴坐标;
    if(isNaN(dx) || isNaN(dz)){this.guardClearMovement();return;}
    if(this.guardMovementTarget!=target._name){
        this.guardAlignZ=this.guardApproachX=false;this.guardMovementTarget=target._name;
    }
    var tune:Object=this.guardTuning,ax:Number=Math.abs(dx),az:Number=Math.abs(dz);
    if(az>tune.laneRange)this.guardAlignZ=true;
    else if(az<=tune.laneStopRange)this.guardAlignZ=false;
    if(ax>tune.shootRange)this.guardApproachX=true;
    else if(ax<=tune.approachStopRange)this.guardApproachX=false;
    this.上行=this.guardAlignZ && dz<0;this.下行=this.guardAlignZ && dz>0;
    this.左行=this.guardApproachX && dx<0;this.右行=this.guardApproachX && dx>0;
};

行走=function():Void {
    if(_root.暂停)return;
    if(_root.控制目标==this._name && _root.控制目标全自动==false){
        _root.敌人函数.行走.call(this);return;
    }
    if(!(this.hp>0) || this.浮空 || this.倒地 || this.硬直中
        || this.guardAttackOwner!=null){this.guardClearMovement();return;}
    if(this.状态!="空手站立" && this.状态!="空手行走" && this.状态!="空手跑")return;
    // Re-evaluate at the movement consumer on every frame, after any generic AI write.
    this.guardUpdateMovement();
    var target:MovieClip=_root.gameworld[this.攻击目标];
    var movingX:Boolean=this.左行 || this.右行,movingZ:Boolean=this.上行 || this.下行;
    var running:Boolean=movingX && Math.abs(target._x-this._x)>this.guardTuning.shootRange;
    if(movingX){
        var direction:String=this.右行?"右":"左";this.方向改变(direction);
        var speedX:Number=running?this.跑X速度:this.行走X速度;
        this.移动(direction,Math.min(speedX,Math.max(0,Math.abs(target._x-this._x)-this.guardTuning.approachStopRange)));
    }
    if(movingZ){
        var speedZ:Number=running?this.跑Y速度:this.行走Y速度;
        this.移动(this.下行?"下":"上",Math.min(speedZ,Math.max(0,Math.abs(target.Z轴坐标-this.Z轴坐标)-this.guardTuning.laneStopRange)));
    }
    this.状态改变(movingX || movingZ?(running?"空手跑":"空手行走"):"空手站立");
};

guardReleaseStance=function():Void {
    var owner:Object=this.guardAttackOwner;
    if(owner==null || !owner.ownsStance)return;
    this.刚体=owner.previousRigid;this.免疫击退=owner.previousImmune;owner.ownsStance=false;
};

guardCancelAttack=function(keepFollowup:Boolean):Void {
    this.guardReleaseStance();
    if(this.guardAttackOwner!=null)this.guardAttackOwner.active=false;
    this.guardAttackOwner=null;this.动作A=false;this.guardCombo=null;
    if(keepFollowup!==true)this.guardPendingFollowup=null;
};

// 在旧身体卸载前取消，旧动作不能借用新身体继续开火。
状态改变=function(next:String):Void {
    if(this.guardTransform!=null){
        if(next=="消失"){
            this.guardTransform.active=false;
            if(this.guardTransform.child._parent===this._parent)this.guardTransform.child._visible=true;
        }else return;
    }
    if(next=="血腥死" && this.hp<=0 && this.光头保安变身!==false){this.guardStartTransform();return;}
    if(this.状态==next)return;
    this.guardCancelAttack(next=="空手攻击" && this.guardPendingFollowup!=null);this.状态=next;this.gotoAndStop(next);
};

guardBeginAttack=function(body:MovieClip):Void {
    var queued:Object=this.guardPendingFollowup;
    var followup:Boolean=this.状态=="空手攻击" && body._currentframe==88;
    this.guardCancelAttack();
    if(!(this.hp>0) || (this.状态!="空手攻击" && this.状态!="近战")){body.stop();return;}
    if(followup && this.guardFollowupTarget(queued)==null){body.stop();this.动画完毕();return;}
    var token:Object={};body.guardToken=token;
    var mode:String=this.状态=="近战"?"melee":followup?"followup":"shoot";
    if(followup)this.guardFollowupCount++;
    if(mode=="melee")this.guardNextMelee=this.guardClock+this.guardTuning.meleeCooldown;
    this.guardAttackOwner={token:token,active:true,state:this.状态,mode:mode,fired:false,
        releaseFrame:mode=="melee"?22:mode=="followup"?96:41,
        previousRigid:this.刚体===true,previousImmune:this.免疫击退===true,ownsStance:true};
    // 举枪或起手挥砸期间稳住身体；出弹/砸击立即撤回，不减免任何伤害。
    this.刚体=true;this.免疫击退=true;
    this.guardAttackCount++;this.guardClearMovement();
};

guardCanAct=function(body:MovieClip):Boolean {
    var owner:Object=this.guardAttackOwner;
    return !_root.暂停 && this.hp>0 && owner!=null && owner.active
        && this.man===body && body.guardToken===owner.token && this.状态==owner.state;
};

guardFindMuzzle=function(body:MovieClip):Object {
    var gun:MovieClip=body.guardGun;
    if(gun==null || gun._parent!==body)return null;
    // SPAS12 枪口 (302.8,-34.05) 经过唯一 0.6 缩放；无需等待新置入枪身的子层首帧。
    var p:Object={x:181.68,y:-20.43};gun.localToGlobal(p);
    p.globalY=p.y;_root.gameworld.globalToLocal(p);
    return isNaN(p.x) || isNaN(p.y)?null:p;
};

guardShoot=function(body:MovieClip):Void {
    if(!this.guardCanAct(body))return;
    var owner:Object=this.guardAttackOwner;
    if(owner.fired || (owner.mode=="followup"?body._currentframe!=96:(owner.mode!="shoot" || body._currentframe!=41)))return;
    var p:Object=this.guardFindMuzzle(body);
    if(p==null){this.guardInvalidMuzzleCount++;return;}
    this.guardAttackOwner.fired=true;
    var bullet:Object=_root.子弹属性初始化(body.guardGun,"穿刺子弹",this);
    bullet.shootX=p.x;bullet.shootY=p.y;bullet.转换中间y=p.globalY;
    bullet.声音="re_shotgun_spas12.wav";bullet.霰弹值=this.guardTuning.pellets;bullet.子弹散射度=8;
    bullet.子弹威力=this.空手攻击力;bullet.子弹速度=25;
    bullet.Z轴攻击范围=24;bullet.击倒率=10;bullet.发射效果="霰弹枪枪火";
    bullet.区域定位area=undefined;
    this.guardShotCount++;_root.子弹区域shoot传递(bullet);this.guardReleaseStance();
};

guardMeleeHit=function(body:MovieClip):Void {
    if(!this.guardCanAct(body) || this.guardAttackOwner.mode!="melee" || body._currentframe!=22 || this.guardAttackOwner.fired)return;
    this.guardAttackOwner.fired=true;
    var bullet:Object=_root.子弹属性初始化(body,"近战子弹",this);
    var dir:Number=this.方向=="左"?-1:1;
    bullet.shootX=this._x+dir*48;bullet.shootY=this._y-48;bullet.转换中间y=this.Z轴坐标;
    bullet.声音="re_hit_blunt.wav";bullet.霰弹值=1;bullet.子弹散射度=0;
    bullet.子弹威力=this.空手攻击力*1.5;bullet.子弹速度=0;
    bullet.Z轴攻击范围=28;bullet.击倒率=2;bullet.水平击退速度=28;bullet.垂直击退速度=0;bullet.发射效果="";
    bullet.区域定位area=body.guardMeleeArea;
    bullet.guardShooterIdentity=this.guardIdentity;bullet.guardAttackToken=this.guardAttackOwner.token;
    bullet.击中时触发函数=function():Void {
        if(this.guardMeleeShockSpent===true)return;
        this.guardMeleeShockSpent=true;
        var shooter:MovieClip=_root.gameworld[this.发射者],target:MovieClip=this.hitTarget;
        var owner:Object=shooter.guardAttackOwner;
        if(!(shooter.hp>0) || shooter.guardIdentity!==this.guardShooterIdentity
            || target._parent!==shooter._parent || !(target.hp>0) || target.area==null
            || owner==null || !owner.active || owner.mode!="melee" || owner.token!==this.guardAttackToken)return;
        if(target.__guardActionIdentity==undefined)target.__guardActionIdentity={};
        shooter.guardCombo={target:target._name,identity:target.__guardActionIdentity,
            expires:shooter.guardClock+shooter.guardTuning.followupWindow};
        shooter.guardReadyAt=0;
        shooter.guardNextMelee=shooter.guardClock+shooter.guardTuning.meleeCooldown;
    };
    this.guardMeleeCount++;_root.子弹区域shoot传递(bullet);this.guardReleaseStance();
};

// 只有本次枪托真实命中的同实例目标能授权接枪；MISS、换目标、换世界及中断不借用资格。
guardFollowupTarget=function(combo:Object):MovieClip {
    if(combo==null || !(this.hp>0) || this.guardClock>combo.expires || this.攻击目标!=combo.target)return null;
    var target:MovieClip=_root.gameworld[combo.target];
    if(!(target.hp>0) || target._parent!==this._parent || target.area==null || target.__guardActionIdentity!==combo.identity)return null;
    var dx:Number=target._x-this._x,dz:Number=target.Z轴坐标-this.Z轴坐标;
    var height:Number=target.Z轴坐标-target._y;
    if(target.浮空高度!=undefined && !isNaN(target.浮空高度) && target.浮空高度>0)height+=target.浮空高度;
    if(isNaN(dx) || isNaN(dz) || isNaN(height) || Math.abs(dx)>this.guardTuning.followupRange
        || Math.abs(dz)>this.guardTuning.laneRange || height>this.guardTuning.maximumTargetHeight)return null;
    return target;
};

guardFinishAttack=function(body:MovieClip):Void {
    if(!this.guardCanAct(body))return;
    var combo:Object=this.guardCombo;
    var target:MovieClip=this.guardAttackOwner.mode=="melee"?this.guardFollowupTarget(combo):null;
    this.guardCancelAttack();
    if(target!=null){
        // 枪托仍播完 40 帧；专用八帧举枪过渡接原射击及完整回收，不重播普通 40 帧起手。
        this.guardPendingFollowup=combo;
        this.方向改变(target._x<this._x?"左":"右");
        this.状态改变("空手攻击");return;
    }
    this.guardReadyAt=this.guardClock+this.guardTuning.recoveryFrames;
    this.动画完毕();
};

guardTick=function():Void {
    if(_root.暂停 || this.guardTransform!=null)return;
    this.guardClock++;
    if(!isNaN(this.hp) && this.hp<=0){
        this.guardCancelAttack();
        if(this.浮空 || this.状态=="击倒")return;
        if(this.状态=="倒地" && this.光头保安变身===false)return;
        if(!this._killed && typeof(_root.敌人函数.标准击杀)=="function")_root.敌人函数.标准击杀(this);
        else if(this.状态!="血腥死" && this.状态!="消失")this.状态改变("血腥死");
        return;
    }
    var owner:Object=this.guardAttackOwner;
    if(owner!=null && !this.guardCanAct(this.man)){
        this.guardCancelAttack();return;
    }
    if(!(this.hp>0) || this.倒地 || this.浮空 || this.硬直中)return;
    if(owner!=null){
        if(owner.mode=="melee" && this.man._currentframe>=10 && this.man._currentframe<=21){
            var meleeTarget:MovieClip=_root.gameworld[this.攻击目标];
            if(meleeTarget!=null && meleeTarget.hp>0 && !isNaN(meleeTarget._x)){
                var mdx:Number=(meleeTarget._x-this._x)*(this.方向=="左"?-1:1);
                if(mdx>65)this.移动(this.方向,Math.min(4,mdx-65));
            }
        }
        if(this.man._currentframe>owner.releaseFrame)this.guardReleaseStance();
        this.man.nextFrame();return;
    }
    if(_root.控制目标==this._name && _root.控制目标全自动==false)return;
    if(this.状态!="空手站立" && this.状态!="空手行走" && this.状态!="空手跑")return;
    if((this.guardClock&3)!=0)return;
    this.x轴攻击范围=0;this.y轴攻击范围=this.guardTuning.laneRange;
    this.x轴保持距离=this.guardTuning.approachStopRange;
    if(this.unitAI.data!=null){
        this.unitAI.data.xrange=0;this.unitAI.data.zrange=this.y轴攻击范围;
        this.unitAI.data.xdistance=this.x轴保持距离;
    }
    var target:MovieClip=_root.gameworld[this.攻击目标];
    if(!(target.hp>0) || target===this || target.area==null){this.guardClearMovement();return;}
    var dx:Number=target._x-this._x,dz:Number=target.Z轴坐标-this.Z轴坐标;
    var height:Number=target.Z轴坐标-target._y;
    if(target.浮空高度!=undefined && !isNaN(target.浮空高度) && target.浮空高度>0)height+=target.浮空高度;
    if(isNaN(dx) || isNaN(dz) || isNaN(height))return;
    if(this.guardTargetName!=target._name){
        this.guardTargetName=target._name;this.guardReadyAt=this.guardClock+this.guardTuning.reactionFrames;
    }
    if(Math.abs(dx)>this.guardTuning.shootRange || Math.abs(dz)>this.guardTuning.laneRange
        || height>this.guardTuning.maximumTargetHeight || this.guardClock<this.guardReadyAt){
        this.guardUpdateMovement();return;
    }
    this.guardClearMovement();
    if(dx<0)this.方向改变("左");else if(dx>0)this.方向改变("右");
    this.状态改变(Math.abs(dx)<=this.guardTuning.meleeRange && !(this.guardClock<this.guardNextMelee)?"近战":"空手攻击");
};
