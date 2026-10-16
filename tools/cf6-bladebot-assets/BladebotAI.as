// 起手到发力段同时持有刚体与抗位移；收招恢复原状态，不减免伤害。
// 大刀机器人私有近战：CF6 重劈和横扫，CF7 仇恨、移动、碰撞与死亡权威。
bladebotClock=0;
bladebotReadyAt=6;
bladebotNextSweep=0;
bladebotTargetName="";
bladebotAttackOwner=null;
bladebotAttackCount=0;
bladebotHitCount=0;
bladebotDeathFxPlayed=false;
bladebotTuning={cleaveRange:245,sweepRange:145,laneRange:30,keepDistance:185,
    reactionFrames:6,recoveryFrames:0,sweepCooldown:75,maximumTargetHeight:150,airSweepRange:190,cleaveTargetHeight:80};

bladebotCancelAttack=function():Void {
    var owner:Object=this.bladebotAttackOwner;
    if(owner==null) return;
    owner.active=false;
    if(owner.ownsRigid) {this.刚体=owner.previousRigid;this.免疫击退=owner.previousImmune;}
    this.bladebotAttackOwner=null;
};

bladebotBeginAttack=function(body:MovieClip,action:String):Void {
    this.bladebotCancelAttack();
    if(!(this.hp>0)) {body.stop();return;}
    var token:Object={}; body.bladebotToken=token;
    this.bladebotAttackOwner={token:token,action:action,active:true,
        previousRigid:this.刚体===true,previousImmune:this.免疫击退===true,ownsRigid:true,lastHitFrame:0,target:this.攻击目标};
    this.刚体=true;this.免疫击退=true;
    this.bladebotAttackCount++;
    if(action=="sweep") this.bladebotNextSweep=this.bladebotClock+this.bladebotTuning.sweepCooldown;
};

bladebotCanAct=function(body:MovieClip):Boolean {
    var owner:Object=this.bladebotAttackOwner;
    return !_root.暂停 && this.hp>0 && !this.硬直中 && owner!=null && owner.active
        && body===this.man && body.bladebotToken===owner.token
        && this.状态==(owner.action=="sweep"?"近战":"空手攻击");
};

bladebotFinishAttack=function(body:MovieClip):Void {
    var owner:Object=this.bladebotAttackOwner;
    if(owner==null || body!==this.man || owner.token!==body.bladebotToken) return;
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
    if(isNaN(dx) || isNaN(dz) || Math.abs(dz)>this.bladebotTuning.laneRange) return;
    if((this.方向=="右" && dx>185) || (this.方向=="左" && dx< -185)) {
        this.移动(this.方向,Math.min(amount,Math.abs(dx)-185));
    }
};

bladebotStrike=function(body:MovieClip,point:MovieClip,multiplier:Number):Void {
    if(!this.bladebotCanAct(body) || point.area==null) return;
    var owner:Object=this.bladebotAttackOwner;
    if(owner.lastHitFrame==body._currentframe) return;
    owner.lastHitFrame=body._currentframe;
    var p:Object={x:point._x,y:point._y};
    body.localToGlobal(p); _root.gameworld.globalToLocal(p);
    var heavy:Boolean=owner.action=="cleave";
    this.bladebotHitCount++;
    _root.子弹区域shoot传递({声音:"",霰弹值:1,子弹散射度:0,发射效果:"",
        子弹种类:"近战子弹",子弹威力:this.空手攻击力*multiplier,子弹速度:0,
        Z轴攻击范围:30,击中地图效果:"",发射者:this._name,shootX:p.x,shootY:p.y,
        shootZ:this.Z轴坐标,击倒率:heavy?3:10,击中后子弹的效果:"空手攻击火花",
        水平击退速度:heavy?8:3,垂直击退速度:heavy?5:2,区域定位area:point.area});
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
    return "none";
};

bladebotDeathFx=function():Void {
    if(this.bladebotDeathFxPlayed) return;
    this.bladebotDeathFxPlayed=true;
    // 使用已装载 CF7 表现；不复制旧 CF6 混淆脚本，也不产生死亡伤害。
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
        var state:String=owner.action=="sweep"?"近战":"空手攻击";
        if(this.状态!=state || this.man.bladebotToken!==owner.token) this.bladebotCancelAttack();
        else {
            var frame:Number=this.man._currentframe;
            var active:Boolean=owner.action=="sweep"?(frame>=1 && frame<=40):(frame>=1 && frame<=30);
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
    var action:String=this.bladebotChooseAttack(Math.abs(dx),Math.abs(dz),height);
    if(action=="none") {
        this.上行=dz< -6;this.下行=dz>6;
        this.左行=dx< -this.bladebotTuning.keepDistance;this.右行=dx>this.bladebotTuning.keepDistance;
        if(Math.abs(dx)>260 && this.状态!="空手跑") this.状态改变("空手跑");
        return;
    }
    this.左行=this.右行=this.上行=this.下行=false;
    if(dx<0) this.方向改变("左"); else if(dx>0) this.方向改变("右");
    this.状态改变(action=="sweep"?"近战":"空手攻击");
};
