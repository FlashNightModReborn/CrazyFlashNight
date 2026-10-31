// Ordinary positional combat and elite shield mobility share existing weapon services.
soldierNextMeleeAt=0;soldierNextBashAt=0;soldierNextGrenadeAt=90;
soldierBashCount=0;soldierGrenadeCount=0;soldierChargeCount=0;soldierDebrisStampCount=0;
soldierGrenadeError="";soldierMeleeKind="knife";
soldierTuning.bashRange=60;soldierTuning.bashRestFrames=90;soldierTuning.meleeRestFrames=18;
soldierTuning.chargeRange=650;soldierTuning.chargeStopRange=130;soldierTuning.chargeStageRange=230;
soldierRoleChoose=soldierChooseAttack;soldierRoleDrive=soldierDriveShooting;
soldierRoleCanAct=soldierCanAct;soldierRoleReload=soldierReloadStart;
soldierRoleInitialize=soldierInitializePhase;soldierRoleBreak=soldierFinishBreak;
soldierRoleFinish=soldierFinishAttack;soldierRoleMove=soldierUpdateMovement;
soldierRoleWalk=行走;

soldierInitializePhase=function():Void {
    if(this.特种兵投掷物==undefined)this.特种兵投掷物="高爆手雷";
    var frames:Number=Number(this.特种兵投掷冷却帧);
    this.soldierGrenadeRest=isFinite(frames) && frames>=36?frames:210;
    this.soldierRoleInitialize();
};
soldierCanGrenade=function():Boolean {
    if((this.soldierIsElite===true && this.soldierIsInstructor!==true) || this.soldierPhase!=2 || this.特种兵投掷物===false || this.特种兵投掷物=="")return false;
    var item:Object=_root.getItemData(this.特种兵投掷物),data:Object=item.data;
    return item.use=="手雷" && typeof data.bullet=="string" && data.bullet!="" && isFinite(data.power) && data.power>0;
};
soldierChooseAttack=function(dx:Number,dz:Number,height:Number):String {
    var tune:Object=this.soldierTuning;
    if(isNaN(dx) || isNaN(dz) || isNaN(height) || dx<0 || dz<0
        || height>tune.maximumTargetHeight || this.soldierClock<this.soldierReadyAt)return "none";
    if(this.soldierIsElite===true && this.soldierPhase==1){
        return dz<=tune.laneRange && dx>=tune.chargeStageRange && dx<=tune.chargeRange
            && !(this.soldierClock<this.soldierNextShootAt)?"shoot":"none";
    }
    if(dx>=180 && dx<=480 && dz<=80 && !(this.soldierClock<this.soldierNextGrenadeAt)
        && this.soldierCanGrenade())return "grenade";
    if(dx<=tune.knifeRange && dz<=tune.laneRange){
        if(this.soldierClock<this.soldierNextMeleeAt)return "none";
        this.soldierMeleeKind=this.soldierPhase==1 && dx<=tune.bashRange
            && !(this.soldierClock<this.soldierNextBashAt)?"bash":"knife";
        return "knife";
    }
    return this.soldierRoleChoose(dx,dz,height);
};
soldierCanAct=function(body:MovieClip):Boolean {
    var owner:Object=this.soldierAttackOwner;
    if(owner.action!="grenade")return this.soldierRoleCanAct(body);
    return !_root.暂停 && this.hp>0 && this.soldierPhase==2 && !this.硬直中
        && !this.倒地 && !this.浮空 && owner.active && owner.version===this.version
        && body===this.man && body.soldierToken===owner.token && this.状态=="投掷手雷"
        && owner.itemName===this.特种兵投掷物 && (this.soldierIsElite!==true || this.soldierIsInstructor===true);
};
soldierBeginMelee=function(body:MovieClip):Void {
    if(this.soldierIsElite===true && this.soldierIsInstructor!==true){body.stop();this.动画完毕();return;}
    this.soldierBeginAttack(body,"knife");
    var owner:Object=this.soldierAttackOwner;
    if(owner==null)return;
    owner.bash=this.soldierMeleeKind=="bash";
    this.soldierNextMeleeAt=this.soldierClock+34+this.soldierTuning.meleeRestFrames;
    if(owner.bash){this.soldierNextBashAt=this.soldierClock+this.soldierTuning.bashRestFrames;body.gotoAndPlay("挥盾");}
};
soldierMeleeHit=function(body:MovieClip,point:MovieClip):Void {
    if(!this.soldierCanAct(body) || point.area==null)return;
    var owner:Object=this.soldierAttackOwner;
    if(owner.action!="knife" || owner.meleeCommitted)return;
    owner.meleeCommitted=true;
    if(!owner.bash){this.soldierStab(body,point);return;}
    var p:Object={x:point._x,y:point._y};body.localToGlobal(p);_root.gameworld.globalToLocal(p);
    this.soldierBashCount++;
    _root.子弹区域shoot传递({声音:"",霰弹值:1,子弹散射度:0,发射效果:"",子弹种类:"近战子弹",
        子弹威力:this.空手攻击力*0.6,子弹速度:0,暴击:function(bullet:Object):Number {return 1;},斩杀:0,Z轴攻击范围:24,
        发射者:this._name,shootX:p.x,shootY:p.y,shootZ:this.Z轴坐标,击倒率:10,
        击中地图效果:"",击中后子弹的效果:"空手攻击火花",水平击退速度:24,垂直击退速度:0,区域定位area:point.area});
};
soldierFinishAttack=function(body:MovieClip):Void {
    var owner:Object=this.soldierAttackOwner;
    if(owner.action=="knife" && body===this.man && owner.token===body.soldierToken)
        this.soldierNextMeleeAt=this.soldierClock+this.soldierTuning.meleeRestFrames;
    this.soldierRoleFinish(body);
};
soldierBeginGrenade=function(body:MovieClip):Void {
    this.soldierCancelAttack();
    if(!this.soldierCanGrenade() || !(this.hp>0)){body.stop();this.动画完毕();return;}
    var token:Object={};body.soldierToken=token;
    var target:MovieClip=_root.gameworld[this.攻击目标];
    this.soldierAttackOwner={token:token,action:"grenade",active:true,version:this.version,
        itemName:this.特种兵投掷物,targetX:target._x,sign:this.方向=="左"?-1:1,thrown:false,age:0};
    this.soldierNextGrenadeAt=this.soldierClock+this.soldierGrenadeRest;body.stop();
};
soldierDriveGrenade=function(body:MovieClip):Void {
    var owner:Object=this.soldierAttackOwner;
    owner.age++;
    if(owner.age>=36){this.soldierFinishAttack(body);return;}
    body.gotoAndStop(owner.age+1);
    if(owner.age>=24 && !owner.thrown)this.soldierThrowGrenade(body);
};
soldierThrowGrenade=function(body:MovieClip):Void {
    if(!this.soldierCanAct(body))return;
    var owner:Object=this.soldierAttackOwner;
    if(owner.thrown)return;
    owner.thrown=true;
    var data:Object=_root.getItemData(owner.itemName).data;
    if(!(data.power>0) || typeof data.bullet!="string"){this.soldierGrenadeError="投掷物配置失效";return;}
    var gravity:Number=Number(_root.重力加速度);
    if(!(gravity>0))gravity=1;
    // The grenade asset owns its -5 vertical launch and gravity. Match the
    // horizontal travel to that flight, keeping the throw a committed aim.
    var release:Object={x:0,y:0};body.投掷手.localToGlobal(release);_root.gameworld.globalToLocal(release);
    if(!isFinite(release.x) || !isFinite(release.y)){this.soldierGrenadeError="投掷手挂点失效";return;}
    var height:Number=Math.max(1,this.Z轴坐标-release.y);
    var flight:Number=(5+Math.sqrt(25+2*height*gravity))/gravity;
    var distance:Number=Math.abs(owner.targetX-release.x);
    if(!isFinite(distance))distance=300;
    var velocity:Number=Math.min(Number(data.velocity)>0?Number(data.velocity):25,Math.max(4,distance/flight));
    var bullet:MovieClip=_root.子弹区域shoot传递({声音:"",霰弹值:1,子弹散射度:0,发射效果:"",
        子弹种类:data.bullet,子弹威力:Number(data.power),子弹速度:velocity,
        速度X:owner.sign*velocity,速度Y:0,子弹大小:data.bulletsize,
        Z轴攻击范围:10,击倒率:10,发射者:this._name,发射者名:this._name,
        子弹敌我属性值:this.是否为敌人,shootX:release.x,
        shootY:release.y,shootZ:this.Z轴坐标,击中地图效果:"",击中后子弹的效果:""});
    if(bullet!=null)this.soldierGrenadeCount++;else this.soldierGrenadeError="投掷物资源未加载";
};
soldierBeginCharge=function(body:MovieClip):Void {
    this.soldierBeginAttack(body,"shoot");
    var owner:Object=this.soldierAttackOwner;
    if(owner==null)return;
    if(this.soldierIsElite!==true || this.soldierPhase!=1){this.soldierFinishAttack(body);return;}
    owner.charge=!this.soldierShieldCoverFire;owner.coverFire=this.soldierShieldCoverFire===true;owner.age=0;owner.distance=0;owner.blockedFrames=0;owner.lastChargeX=this._x;
    owner.sign=this.方向=="左"?-1:1;
    var config:Object=this.soldierTacticalConfig;
    owner.shotLimit=config.chargeShots;owner.turns=0;owner.chargeMovedZ=0;
    owner.fireDeadline=this.soldierClock+(owner.coverFire?config.rifleFireFrames:config.chargeWindupFrames+config.chargeActiveFrames);
    this.soldierNextShootAt=owner.fireDeadline+(owner.coverFire?config.rifleRestFrames:config.chargeRestFrames);
    if(owner.charge)this.soldierChargeCount++;
    body.prepareStandardShotPose=function(frame:String):Void {};
    body.stop();
};
soldierDriveShooting=function(body:MovieClip):Void {
    var owner:Object=this.soldierAttackOwner;
    if(!owner.charge){this.soldierRoleDrive(body);return;}
    if(owner.reload){_root.主角函数.换弹帧率控制(body);return;}
    owner.age++;
    var config:Object=this.soldierTacticalConfig;
    var windup:Number=config.chargeWindupFrames,active:Number=config.chargeActiveFrames;
    if(owner.age>=windup+active+config.chargeRecoveryFrames){this.soldierFinishAttack(body);return;}
    if(owner.age<windup){body.gotoAndStop(1+Math.floor(owner.age*9/windup));return;}
    if(owner.age>=windup+active){
        body.gotoAndStop(Math.min(46,35+Math.floor((owner.age-windup-active)*11/config.chargeRecoveryFrames)));
        this.动作A=false;_root.主角函数.清理射击任务(this);return;
    }
    body.gotoAndStop(11+Math.min(23,Math.floor((owner.age-windup)*24/active)));
    var target:MovieClip=_root.gameworld[owner.target];
    owner.lastChargeX=this._x;
    this.soldierChargeContact(owner);
    // Contact is an impact, not a brake. Finish the committed run through the target.
    if(owner.contactCommitted && target.hp>0 && owner.turns<config.chargeMaxTurns
        && owner.age>owner.contactAge+4 && (target._x-this._x)*owner.sign<-config.chargeTurnDistance){
        owner.sign=-owner.sign;owner.turns++;this.soldierTacticalStats.chargeTurns++;
        this.方向改变(owner.sign<0?"左":"右");
    }
    if(owner.distance>=config.chargeMaxDistance || owner.blockedFrames>=3){
        owner.age=windup+active;body.gotoAndStop(35);
        this.动作A=false;_root.主角函数.清理射击任务(this);return;
    }
    if(owner.distance<config.chargeMaxDistance && owner.blockedFrames<3){
        var speed:Number=Math.min(12,Math.max(2,Number(this.跑X速度)*config.chargeSpeed));
        if(!isFinite(speed))speed=7;
        speed=Math.min(speed,config.chargeMaxDistance-owner.distance);
        var moved:Number=this.soldierTacticalMove(owner.sign<0?"左":"右",speed);
        owner.distance+=moved;
        if(target.hp>0 && owner.chargeMovedZ<config.chargeZBudget){
            var dz:Number=target.Z轴坐标-this.Z轴坐标;
            if(Math.abs(dz)>this.soldierTuning.laneStopRange){
                var zstep:Number=Math.min(this.跑Y速度*config.chargeZSpeed,Math.abs(dz)-this.soldierTuning.laneStopRange,
                    config.chargeZBudget-owner.chargeMovedZ);
                owner.chargeMovedZ+=this.soldierTacticalMove(dz<0?"上":"下",zstep);
            }
        }
        if(moved<0.1)owner.blockedFrames++;else owner.blockedFrames=0;
        this.soldierChargeContact(owner);
        if(moved<0.1){owner.age=windup+active;body.gotoAndStop(35);this.动作A=false;_root.主角函数.清理射击任务(this);return;}
    }
    if(owner.shots<owner.shotLimit && this.soldierMuzzleMarker(body)!=null){
        this.动作A=true;body.开始射击();
    }
};
soldierReloadStart=function(body:MovieClip):Void {
    var owner:Object=this.soldierAttackOwner;
    if(!owner.charge && !owner.coverFire){this.soldierRoleReload(body);return;}
    if(!this.soldierCanAct(body)){body.stop();return;}
    this.动作A=false;owner.reload=true;this.soldierReloadCount++;
    _root.主角函数.初始化换弹负担(body,47,67,50,81,[67,79]);
};
soldierUpdateMovement=function():Void {
    if(this.soldierIsElite!==true || this.soldierPhase!=1){this.soldierRoleMove();return;}
    this.soldierRoleMove();
    var target:MovieClip=_root.gameworld[this.攻击目标];
    if(!(target.hp>0))return;
    var dx:Number=target._x-this._x,ax:Number=Math.abs(dx);
    var stop:Number=this.soldierTacticalConfig.chargeRange-40;
    this.左行=ax>stop && dx<0;this.右行=ax>stop && dx>0;
};
行走=function():Void {
    if(this.soldierIsElite!==true || this.soldierPhase!=1
        || (_root.控制目标==this._name && _root.控制目标全自动==false)){this.soldierRoleWalk();return;}
    if(_root.暂停 || !(this.hp>0) || this.硬直中 || this.soldierAttackOwner!=null)return;
    if(this.状态!="长枪站立" && this.状态!="长枪行走" && this.状态!="长枪跑")return;
    this.soldierUpdateMovement();
    var target:MovieClip=_root.gameworld[this.攻击目标];
    if(!(target.hp>0))return;
    var dx:Number=target._x-this._x,dz:Number=target.Z轴坐标-this.Z轴坐标;
    if(dx!=0)this.方向改变(dx<0?"左":"右");
    var moving:Boolean=this.左行 || this.右行 || this.上行 || this.下行;
    if(this.左行 || this.右行)this.移动(this.右行?"右":"左",Math.min(this.行走X速度,Math.max(0,Math.abs(dx)-(this.soldierTacticalConfig.chargeRange-40))));
    if(this.上行 || this.下行)this.移动(this.下行?"下":"上",Math.min(this.行走Y速度,Math.max(0,Math.abs(dz)-12)));
    this.状态改变(moving?"长枪行走":"长枪站立");
};
soldierFinishBreak=function(body:MovieClip):Void {
    if(!_root.暂停 && this.soldierPhase==0 && body===this.man
        && body.soldierPhaseToken===this.soldierPhaseToken && !this.soldierDebrisStamped){
        var debris:MovieClip=body.盾碎片;
        if(debris!=null && _root.gameworld.deadbody.layers[2]!=null && typeof _root.add2map=="function"){
            _root.add2map(debris,2);this.soldierDebrisStampCount++;
        }
        this.soldierDebrisStamped=true;
    }
    this.soldierRoleBreak(body);
};
