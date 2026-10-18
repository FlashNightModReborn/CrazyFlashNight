// 两个形态共用私有动作时钟；仇恨、碰撞、伤害和结算仍由 CF7 执行。
elderClock=0;elderReadyAt=6;elderTargetName="";elderAttackOwner=null;
elderAttackCount=0;elderHitCount=0;elderFxMask=0;elderIdentity={};
elderCombatReported=false;
elderCombatStats={burstStarts:0,burstContacts:0,stabStarts:0,stabContacts:0,
    beamStarts:0,beamContacts:0,kicksStarts:0,kicksContacts:0,slamStarts:0,slamContacts:0};
elderAlignZ=false;elderApproachX=false;elderMovementTarget="";
elderTuning={shootRange:elderForm=="human"?500:550,approachStopRange:elderForm=="human"?330:430,
    laneRange:30,laneStopRange:10,reactionFrames:6,recoveryFrames:6,maximumTargetHeight:140,
    closeRange:elderForm=="human"?175:150,slamRange:220,slamCooldown:120};
elderNextSlam=0;
elderActions=elderForm=="human"?
    {burst:{state:"空手攻击",hits:[13,21,29,37],power:1},stab:{state:"近战",hits:[7],power:1}}:
    {beam:{state:"空手攻击",hits:[29],power:1},kicks:{state:"近战",hits:[9,26],power:1},slam:{state:"重击",hits:[37],power:1}};

elderClearMovement=function():Void {
    this.左行=this.右行=this.上行=this.下行=false;this.elderAlignZ=this.elderApproachX=false;
};
elderCancelAttack=function():Void {
    if(this.elderAttackOwner!=null){
        if(this.elderAttackOwner.ownsRigid)this.刚体=this.elderAttackOwner.previousRigid;
        if(this.elderAttackOwner.ownsImmune)this.免疫击退=this.elderAttackOwner.previousImmune;
        this.elderAttackOwner.active=false;
    }
    this.elderAttackOwner=null;this.动作A=false;
};
// 每个形态结束时只记录一次出手诊断；接触计数不是实际命中或累计伤害。
elderReportCombat=function():Void {
    if(this.elderCombatReported)return;
    this.elderCombatReported=true;
    var target:MovieClip=_root.gameworld[this.攻击目标],stats:Object=this.elderCombatStats;
    var message:String="[CF6_ELDER_COMBAT_END] unit="+this._name+" form="+this.elderForm+" level="+this.等级
        +" clock="+this.elderClock+" starts="+this.elderAttackCount+" contacts="+this.elderHitCount
        +" beam="+stats.beamStarts+"/"+stats.beamContacts+" kicks="+stats.kicksStarts+"/"+stats.kicksContacts
        +" slam="+stats.slamStarts+"/"+stats.slamContacts+" burst="+stats.burstStarts+"/"+stats.burstContacts
        +" stab="+stats.stabStarts+"/"+stats.stabContacts+" x="+this._x+" z="+this.Z轴坐标
        +" target="+this.攻击目标+" targetHp="+target.hp+" targetX="+target._x+" targetZ="+target.Z轴坐标;
    trace(message);
    if(typeof _root.服务器.发布服务器消息=="function")_root.服务器.发布服务器消息(message);
};
状态改变=function(next:String):Void {
    if(this.elderTransform!=null){
        if(next!="消失")return;
        this.elderTransform.active=false;
        var child:MovieClip=this.elderTransform.child;
        if(child.elderSpawnIdentity===this.elderTransform.spawnIdentity)child._visible=true;
    }
    if(this.hp<=0 && next!="消失"){
        this.elderReportCombat();
        if(this.elderForm=="human" && this.老头变身===true){this.elderStartTransform();return;}
        next="血腥死";
    }
    if(this.elderForm=="robot" && (next=="击倒" || next=="倒地" || next=="被投" || next=="空手跳"))next="被击";
    if(this.elderForm=="robot"){
        this.浮空=this.倒地=false;this.垂直速度=0;
        if(!isNaN(this.Z轴坐标))this._y=this.Z轴坐标;
    }
    if(this.状态==next)return;
    this.elderCancelAttack();this.状态=next;this.gotoAndStop(next);
};
elderBeginAttack=function(body:MovieClip,action:String):Void {
    this.elderCancelAttack();
    var spec:Object=this.elderActions[action];
    if(!(this.hp>0) || spec==undefined || this.状态!=spec.state){body.stop();return;}
    var token:Object={};body.elderToken=token;
    this.elderAttackOwner={token:token,active:true,state:spec.state,action:action,lastHitFrame:0,
        spec:spec,target:this.攻击目标,previousRigid:this.刚体===true,ownsRigid:this.elderForm=="robot",
        previousImmune:this.免疫击退===true,ownsImmune:action=="beam"};
    if(this.elderAttackOwner.ownsRigid)this.刚体=true;
    if(this.elderAttackOwner.ownsImmune)this.免疫击退=true;
    var target:MovieClip=_root.gameworld[this.攻击目标];
    if(target.hp>0){
        if(target.__elderActionIdentity==undefined)target.__elderActionIdentity={};
        this.elderAttackOwner.targetIdentity=target.__elderActionIdentity;
    }
    this.elderCombatStats[action+"Starts"]++;
    this.elderAttackCount++;this.elderClearMovement();
    if(action=="slam")this.elderNextSlam=this.elderClock+this.elderTuning.slamCooldown;
};
elderCanAct=function(body:MovieClip):Boolean {
    var owner:Object=this.elderAttackOwner;
    return !_root.暂停 && this.hp>0 && !this.硬直中 && owner!=null && owner.active
        && this.man===body && body.elderToken===owner.token && this.状态==owner.state;
};
elderContactDue=function(frame:Number):Boolean {
    var frames:Array=this.elderAttackOwner.spec.hits;
    for(var i:Number=0;i<frames.length;i++)if(frames[i]==frame)return true;
    return false;
};
elderStrike=function(body:MovieClip,point:MovieClip):Void {
    if(!this.elderCanAct(body) || point._parent!==body || point.elderToken!==body.elderToken
        || point.elderHitFrame!=body._currentframe || !this.elderContactDue(body._currentframe))return;
    var owner:Object=this.elderAttackOwner,action:String=owner.action;
    if(owner.lastHitFrame>=body._currentframe || (action!="burst" && point.area==null))return;
    var p:Object={x:point._x,y:point._y};body.localToGlobal(p);
    var globalY:Number=p.y;_root.gameworld.globalToLocal(p);
    if(isNaN(p.x) || isNaN(p.y))return;
    owner.lastHitFrame=body._currentframe;this.elderHitCount++;this.elderCombatStats[action+"Contacts"]++;
    var bullet:Object;
    if(action=="burst"){
        bullet=_root.子弹属性初始化(point,"普通子弹",this);
        bullet.子弹速度=30;bullet.子弹散射度=0;bullet.发射效果="突击步枪枪火";
        bullet.击中地图效果="火花";bullet.转换中间y=globalY;
        bullet.区域定位area=undefined;
    }else{
        bullet={声音:"",霰弹值:1,子弹散射度:0,发射效果:"",子弹种类:"近战子弹",
            子弹速度:0,击中地图效果:"",区域定位area:point.area};
    }
    bullet.子弹威力=this.空手攻击力*owner.spec.power;bullet.Z轴攻击范围=30;
    bullet.发射者=this._name;bullet.shootX=p.x;bullet.shootY=p.y;bullet.shootZ=this.Z轴坐标;
    bullet.击倒率=action=="slam"?3:10;bullet.击中后子弹的效果="空手攻击火花";
    bullet.水平击退速度=action=="slam"?6:3;bullet.垂直击退速度=action=="slam"?4:0;
    bullet.伤害类型=action=="beam"?"魔法":"物理";
    bullet.魔法伤害属性=action=="beam"?"波":undefined;
    _root.子弹区域shoot传递(bullet);
};
elderFinishAttack=function(body:MovieClip):Void {
    if(!this.elderCanAct(body))return;
    this.elderCancelAttack();this.elderReadyAt=this.elderClock+this.elderTuning.recoveryFrames;
    this.动画完毕();
};
elderDeathFx=function(bit:Number):Void {
    if((this.elderFxMask&bit)!=0)return;
    this.elderFxMask|=bit;
    _root.效果("火花",this._x,this._y-80,this._xscale*1.4);
    _root.效果("小烟雾",this._x,this._y-80,this._xscale*1.4);
};
// 蓄能前段可缓慢对齐纵深并转向同一目标；发射前六帧锁定，不追加出手。
elderTrackBeam=function(body:MovieClip):Void {
    if(!this.elderCanAct(body))return;
    var owner:Object=this.elderAttackOwner;
    if(owner.action!="beam" || body._currentframe>=owner.spec.hits[0]-6)return;
    var target:MovieClip=_root.gameworld[owner.target];
    if(!(target.hp>0) || target._parent!==this._parent || owner.targetIdentity==undefined
        || target.__elderActionIdentity!==owner.targetIdentity)return;
    var dx:Number=target._x-this._x,dz:Number=target.Z轴坐标-this.Z轴坐标;
    if(isNaN(dx) || isNaN(dz))return;
    if(dx<0)this.方向改变("左");else if(dx>0)this.方向改变("右");
    if(Math.abs(dz)>1 && this.行走Y速度>0)this.移动(dz<0?"上":"下",Math.min(3,Math.min(this.行走Y速度,Math.abs(dz))));
};
// man 内驱动在标准 death 子元件清理后继续负责尸体与阶段交接。
elderBodyTick=function(body:MovieClip):Void {
    if(_root.暂停 || this.man!==body || body.elderMode==undefined)return;
    if(body.elderMode=="phase"){this.elderTransformTick(body);return;}
    if(body.elderMode=="death"){
        if(body._currentframe<body._totalframes)body.nextFrame();
        return;
    }
    if(!(this.hp>0) || this.硬直中)return;
    if(body.elderMode=="attack"){
        if(!this.elderCanAct(body))return;
        var owner:Object=this.elderAttackOwner,frame:Number=body._currentframe;
        this.elderTrackBeam(body);
        if(owner.ownsRigid && frame>owner.spec.hits[owner.spec.hits.length-1]){
            this.刚体=owner.previousRigid;owner.ownsRigid=false;
        }
        if(owner.ownsImmune && frame>owner.spec.hits[owner.spec.hits.length-1]){
            this.免疫击退=owner.previousImmune;owner.ownsImmune=false;
        }
        if(this.elderContactDue(frame) && owner.lastHitFrame<frame){
            this.elderStrike(body,body.攻击点);
            if(owner.lastHitFrame<frame)return;
        }
        if((owner.action=="stab" && frame>7 && frame<17)
            || (owner.action=="kicks" && ((frame>3 && frame<9) || (frame>20 && frame<26)))){
            var target:MovieClip=_root.gameworld[owner.target];
            var dx:Number=target._x-this._x;
            if(target.hp>0 && Math.abs(dx)>90 && Math.abs(target.Z轴坐标-this.Z轴坐标)<30
                && ((this.方向=="右" && dx>0) || (this.方向=="左" && dx<0)))
                this.移动(this.方向,Math.min(8,Math.abs(dx)-90));
        }
    }
    if(body._currentframe==body._totalframes)body.gotoAndStop(1);else body.nextFrame();
};
// 对明确的高波抗目标接近使用实体攻击；不按单位 ID 特判。
elderWantsClose=function(target:MovieClip):Boolean {
    var resistance:Number=Number(target.魔法抗性.波);
    return this.elderForm=="robot" && !isNaN(resistance) && resistance>=75;
};
elderChooseAttack=function(dx:Number,dz:Number,height:Number,preferClose:Boolean):String {
    var tune:Object=this.elderTuning;
    if(isNaN(dx) || isNaN(dz) || isNaN(height) || dx<0 || dz<0 || dz>tune.laneRange
        || height>tune.maximumTargetHeight || this.elderClock<this.elderReadyAt)return "none";
    if(this.elderForm=="human"){
        if(dx<=tune.closeRange && height<=80)return "stab";
        return dx<=tune.shootRange?"burst":"none";
    }
    if(dx<=tune.slamRange && height<=65 && this.elderClock>=this.elderNextSlam)return "slam";
    if(dx<=tune.closeRange && height<=100)return "kicks";
    return !preferClose && dx<=tune.shootRange?"beam":"none";
};
elderTick=function():Void {
    if(_root.暂停 || this.elderTransform!=null)return;
    this.elderClock++;
    if(this.elderForm=="robot"){
        this.浮空=this.倒地=false;this.垂直速度=0;
        if(!isNaN(this.Z轴坐标))this._y=this.Z轴坐标;
    }
    if(!isNaN(this.hp) && this.hp<=0){
        this.elderReportCombat();this.elderCancelAttack();
        if(!this._killed && typeof(_root.敌人函数.标准击杀)=="function")_root.敌人函数.标准击杀(this);
        else if(this.状态!="血腥死" && this.状态!="消失")this.状态改变("血腥死");
        return;
    }
    var owner:Object=this.elderAttackOwner;
    if(owner!=null){
        if(this.状态!=owner.state || this.man.elderToken!==owner.token)this.elderCancelAttack();
        return;
    }
    if(!(this.hp>0) || this.硬直中 || this.浮空 || this.倒地)return;
    if(_root.控制目标==this._name && _root.控制目标全自动==false)return;
    if(this.状态!="空手站立" && this.状态!="空手行走" && this.状态!="空手跑")return;
    if((this.elderClock&3)!=0)return;
    this.x轴攻击范围=0;this.y轴攻击范围=this.elderTuning.laneRange;
    this.x轴保持距离=this.elderTuning.approachStopRange;
    if(this.unitAI.data!=null){this.unitAI.data.xrange=0;this.unitAI.data.zrange=this.y轴攻击范围;this.unitAI.data.xdistance=this.x轴保持距离;}
    var target:MovieClip=_root.gameworld[this.攻击目标];
    if(!(target.hp>0) || target===this || target.area==null){this.elderClearMovement();return;}
    var dx:Number=target._x-this._x,dz:Number=target.Z轴坐标-this.Z轴坐标;
    var height:Number=target.Z轴坐标-target._y;
    if(target.浮空高度>0)height+=target.浮空高度;
    if(this.elderTargetName!=target._name){this.elderTargetName=target._name;this.elderReadyAt=this.elderClock+this.elderTuning.reactionFrames;}
    var action:String=this.elderChooseAttack(Math.abs(dx),Math.abs(dz),height,this.elderWantsClose(target));
    if(action=="none"){this.elderUpdateMovement();return;}
    this.elderClearMovement();
    if(dx<0)this.方向改变("左");else if(dx>0)this.方向改变("右");
    this.状态改变(this.elderActions[action].state);
};
elderUpdateMovement=function():Void {
    this.左行=this.右行=this.上行=this.下行=false;
    var target:MovieClip=_root.gameworld[this.攻击目标];
    if(!(target.hp>0) || target===this || target.area==null){this.elderClearMovement();return;}
    var dx:Number=target._x-this._x,dz:Number=target.Z轴坐标-this.Z轴坐标;
    if(isNaN(dx) || isNaN(dz)){this.elderClearMovement();return;}
    if(this.elderMovementTarget!=target._name){this.elderAlignZ=this.elderApproachX=false;this.elderMovementTarget=target._name;}
    var tune:Object=this.elderTuning,ax:Number=Math.abs(dx),az:Number=Math.abs(dz);
    if(az>tune.laneRange)this.elderAlignZ=true;else if(az<=tune.laneStopRange)this.elderAlignZ=false;
    var preferClose:Boolean=this.elderWantsClose(target);
    var approachRange:Number=preferClose?tune.closeRange:tune.shootRange;
    var stopRange:Number=preferClose?110:tune.approachStopRange;
    if(ax>approachRange)this.elderApproachX=true;else if(ax<=stopRange)this.elderApproachX=false;
    this.上行=this.elderAlignZ && dz<0;this.下行=this.elderAlignZ && dz>0;
    this.左行=this.elderApproachX && dx<0;this.右行=this.elderApproachX && dx>0;
};
行走=function():Void {
    if(_root.暂停)return;
    if(_root.控制目标==this._name && _root.控制目标全自动==false){_root.敌人函数.行走.call(this);return;}
    if(!(this.hp>0) || this.浮空 || this.倒地 || this.硬直中 || this.elderAttackOwner!=null){this.elderClearMovement();return;}
    if(this.状态!="空手站立" && this.状态!="空手行走" && this.状态!="空手跑")return;
    this.elderUpdateMovement();
    var target:MovieClip=_root.gameworld[this.攻击目标];
    var movingX:Boolean=this.左行 || this.右行,movingZ:Boolean=this.上行 || this.下行;
    var running:Boolean=movingX && Math.abs(target._x-this._x)>this.elderTuning.shootRange;
    if(movingX){
        var direction:String=this.右行?"右":"左";this.方向改变(direction);
        var speedX:Number=running?this.跑X速度:this.行走X速度;
        this.移动(direction,Math.min(speedX,Math.max(0,Math.abs(target._x-this._x)-(this.elderWantsClose(target)?110:this.elderTuning.approachStopRange))));
    }
    if(movingZ){
        var speedZ:Number=running?this.跑Y速度:this.行走Y速度;
        this.移动(this.下行?"下":"上",Math.min(speedZ,Math.max(0,Math.abs(target.Z轴坐标-this.Z轴坐标)-this.elderTuning.laneStopRange)));
    }
    this.状态改变(movingX || movingZ?(running?"空手跑":"空手行走"):"空手站立");
};
