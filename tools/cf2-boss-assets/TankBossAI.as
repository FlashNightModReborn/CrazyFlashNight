// 闪2肉鸽前置坦克 Boss。刚体、锁向只由当前动作持有，仍正常承伤。
tankIdentity={};
if(_root.gameworld.__cf2TankWorldIdentity==undefined)_root.gameworld.__cf2TankWorldIdentity={};
tankWorldIdentity=_root.gameworld.__cf2TankWorldIdentity;
tankClock=0;tankReadyAt=12;tankLastTurnAt=-999;tankOwner=null;tankNext={};
tankDeathStarted=false;tankDeathSpent=false;tankDeathFinished=false;
tankMissingPort=0;tankGroundPoint={x:0,y:0};
tankBaseDirection=方向改变;
tankBaseState=状态改变;

tankWorldValid=function():Boolean {
    return this._parent===_root.gameworld && this.tankWorldIdentity!==undefined
        && this.tankWorldIdentity===_root.gameworld.__cf2TankWorldIdentity;
};
tankCancelAttack=function():Void {
    var owner:Object=this.tankOwner;
    if(owner==null)return;
    owner.active=false;
    this.刚体=owner.previousRigid;
    this.免疫击退=owner.previousImmune;
    this.锁定方向=owner.previousLock;
    this.tankOwner=null;
};
方向改变=function(direction:String):Void {
    if(this.tankOwner.active===true && this.hp>0)return;
    this.tankBaseDirection(direction);
};
状态改变=function(state:String):Void {
    if(!(this.hp>0))this.tankCancelAttack();
    if(this.tankOwner.active===true && this.hp>0
        && state!=this.tankOwner.state)return;
    this.tankBaseState(state);
};
tankBeginAttack=function(body:MovieClip,action:String):Void {
    this.tankCancelAttack();
    var spec:Object=this.tankActions[action];
    if(!(this.hp>0) || !this.tankWorldValid()
        || (this.状态!=spec.state && !(action=="melee" && this.状态=="近战"))){body.stop();return;}
    var token:Object={};
    body.tankToken=token;body.tankIdentity=this.tankIdentity;
    this.tankOwner={token:token,active:true,action:action,state:this.状态,spec:spec,loops:1,pulse:0,
        lastDamagePulse:-1,lastMovePulse:-1,previousRigid:this.刚体,previousImmune:this.免疫击退,
        previousLock:this.锁定方向,direction:this.方向,aimDirection:this.方向,moved:0,gunShots:0,laserShots:0};
    this.刚体=true;this.免疫击退=true;this.锁定方向=true;
    this.speed=0;
    this.tankNext[action]=this.tankClock+this.tankTuning[action+"Cooldown"];
    body.stop();
};
tankCanAct=function(body:MovieClip):Boolean {
    var owner:Object=this.tankOwner;
    return !_root.暂停 && this.hp>0 && !this.硬直中 && this.tankWorldValid()
        && body===this.man && body.tankIdentity===this.tankIdentity
        && owner.active===true && owner.token===body.tankToken
        && this.状态===owner.state;
};
tankPort=function(body:MovieClip,kind:String):MovieClip {
    var owner:Object=this.tankOwner;
    var fi:Number=owner.spec.start+body._currentframe-2;
    var slot:Number=this.tankPortMaps[kind][fi];
    var scope:MovieClip=body["tankPort_"+kind];
    scope._visible=false;
    var node:MovieClip=scope["c"+slot];
    if(node==null)return null;
    node.gotoAndStop(fi+1);
    var limit:Number=0;
    while(node.joint!=null && limit<8){
        node=node.joint;node.gotoAndStop(fi+1);limit++;
    }
    return node.point;
};
tankArea=function(body:MovieClip,x:Number,y:Number,width:Number,height:Number):MovieClip {
    var point:MovieClip=body.tankContact;
    if(point==null){point=body.createEmptyMovieClip("tankContact",body.getNextHighestDepth());point.createEmptyMovieClip("area",1);}
    var area:MovieClip=point.area;
    area.clear();area.beginFill(0x00FF00,100);
    area.moveTo(-width/2,-height/2);area.lineTo(width/2,-height/2);
    area.lineTo(width/2,height/2);area.lineTo(-width/2,height/2);area.lineTo(-width/2,-height/2);area.endFill();
    point._x=x;point._y=y;point._visible=false;
    return point;
};
tankSend=function(body:MovieClip,kind:String,power:Number,launcher:Number):Boolean {
    if(!this.tankCanAct(body))return false;
    var owner:Object=this.tankOwner;
    var point:MovieClip;
    if(kind=="melee"){
        // The author slams opposite sides in sequence. Follow each authored
        // impact landmark, not one permanent box in front of the tank.
        var areas:Array=this.tankMeleeAreas;
        for(var i:Number=0;i<areas.length;i++){
            var areaSpec:Array=areas[i];
            if(areaSpec[0]==body._currentframe){
                point=this.tankArea(body,areaSpec[1],areaSpec[2],areaSpec[3],areaSpec[4]);break;
            }
        }
    }else{
        point=this.tankPort(body,kind=="laser"?"beam":kind);
    }
    if(point.area==null){
        this.tankMissingPort++;
        trace("[CF2_TANK_CONTACT_ERROR] "+this._name+" "+kind+" "+body._currentframe);
        return false;
    }
    var world:MovieClip=_root.gameworld;
    var position:Object={x:0,y:0};
    if(kind=="grenade"){
        position.x=this.tankGrenadeMuzzles[launcher][0];
        position.y=this.tankGrenadeMuzzles[launcher][1];
    }
    point.localToGlobal(position);world.globalToLocal(position);
    var ranged:Boolean=kind=="gun" || kind=="cannon" || kind=="grenade";
    var bullet:Object={声音:"",霰弹值:1,子弹散射度:0,发射效果:"",
        子弹种类:kind=="grenade"?"榴弹":kind=="cannon"?"巴雷特子弹":ranged?"加强普通子弹":"近战子弹",
        子弹威力:this.空手攻击力*power,
        子弹速度:kind=="grenade"?5.5+launcher*1.1:kind=="cannon"?72:kind=="gun"?34:0,
        Z轴攻击范围:this.tankTuning.laneRange,发射者:this._name,产生源:this._name,
        shootX:position.x,shootY:position.y,shootZ:this.Z轴坐标,命中率:this.命中率,
        击倒率:kind=="melee"?3:kind=="cannon"?8:kind=="grenade"?16:kind=="laser"?18:22,
        水平击退速度:kind=="melee"||kind=="cannon"?18:kind=="grenade"||kind=="laser"?6:2,
        垂直击退速度:0,
        击中后子弹的效果:kind=="cannon"?"战术巴雷特击中特效":"火花",
        击中地图效果:kind=="cannon"?"弹坑":"",
        区域定位area:point.area,伤害类型:kind=="laser"?"魔法":"物理",
        魔法伤害属性:kind=="laser"?"波":undefined,
        cf2TankAction:owner.action,cf2TankKind:kind,cf2TankLauncher:launcher,
        cf2TankToken:owner.token,cf2TankPulse:owner.pulse};
    if(kind=="grenade"){
        bullet.速度X=(owner.direction=="左"?-1:1)*bullet.子弹速度;
        bullet.速度Y=-6.0+(launcher%5)*0.45;
        bullet.发射效果="发射器枪火";
    }else if(ranged){
        // Follow the visible weapon axis, independent of root facing (the
        // mobile and gatling drawings fire their machinegun backward while
        // the turret cannon fires forward).
        var axis:Object={x:kind=="cannon"?-100:100,y:0};
        point.localToGlobal(axis);world.globalToLocal(axis);
        var nativeAngle:Number=Math.atan2(axis.y-position.y,axis.x-position.x)*180/Math.PI;
        var offset:Number=0;
        var clamp:Number=kind=="cannon"?10:22;
        var target:MovieClip=world[this.攻击目标];
        if(target.hp>0 && target.area!=null && (target._x-position.x)*(axis.x-position.x)>0){
            var bounds:Object=target.area.getBounds(world);
            var dy:Number=(bounds.yMin+bounds.yMax)/2+this.Z轴坐标-target.Z轴坐标-position.y;
            offset=Math.atan2(dy,target._x-position.x)*180/Math.PI-nativeAngle;
            while(offset>180)offset-=360;
            while(offset< -180)offset+=360;
            offset=Math.max(-clamp,Math.min(clamp,offset));
        }
        bullet.fixedRotation=nativeAngle+offset;
        bullet.cf2TankAimOffset=offset;
        // The production muzzle renderer still uses root scale + local offset.
        bullet.角度偏移=bullet.fixedRotation-(this._xscale<0?180:0);
        bullet.发射效果=kind=="cannon"?"巴雷特枪火":"枪火";
    }
    _root.子弹区域shoot传递(bullet);
    if(kind=="melee")_root.播放音效("地震1.wav");
    else if(kind=="grenade" && (launcher%2)==0)_root.播放音效("re_GL_ChinaLake.wav");
    else if(kind=="cannon")_root.播放音效("G1炮开火.wav");
    else if(kind=="gun" && (owner.gunShots++%2)==0)_root.播放音效("re_MG_m249.wav");
    else if(kind=="laser" && (owner.laserShots++%3)==0)_root.播放音效("CF6_0992.mp3");
    return true;
};
tankContactDue=function(action:String,frame:Number):Boolean {
    var spec:Object=this.tankActions[action];
    if(spec.hits!=null){
        var hits:Array=spec.hits;
        for(var i:Number=0;i<hits.length;i++)if(hits[i]==frame)return true;
        return false;
    }
    return (frame>=spec.loopStart && frame<=spec.loopEnd)
        || (spec.brakeHit!=null && frame==spec.brakeHit);
};
tankStrike=function(body:MovieClip):Boolean {
    if(!this.tankCanAct(body))return false;
    var owner:Object=this.tankOwner;
    if(owner.lastDamagePulse==owner.pulse)return true;
    var frame:Number=body._currentframe;
    if(!this.tankContactDue(owner.action,frame))return true;
    // Reserve before calling the production emitter: a synchronous callback
    // cannot replay this pulse, even when several weapons fire together.
    owner.lastDamagePulse=owner.pulse;
    var tune:Object=this.tankTuning;
    var ok:Boolean=true;
    if(owner.action=="melee")ok=this.tankSend(body,"melee",tune.meleePower);
    else if(owner.action=="gatling")ok=this.tankSend(body,"gun",tune.gunPower);
    else if(owner.action=="laser")ok=this.tankSend(body,"laser",tune.laserPower);
    else if(owner.spec.brakeHit!=null && frame==owner.spec.brakeHit){
        ok=this.tankSend(body,"cannon",tune.cannonPower);
    }else{
        var offset:Number=frame-owner.spec.loopStart;
        var cannonOff:Number=owner.spec.cannonOffset!=null?owner.spec.cannonOffset:9;
        if((offset%4)==0)ok=this.tankSend(body,"gun",tune.gunPower);
        if(offset==cannonOff)ok=this.tankSend(body,"cannon",tune.cannonPower) && ok;
        if(offset<40 && (offset%4)==0)ok=this.tankSend(body,"grenade",tune.grenadePower,offset/4) && ok;
        // A beam contact only exists while the actual authored beam is present.
        if(owner.action=="barrage" && (offset%6)==0){
            var beam:MovieClip=this.tankPort(body,"beam");
            if(beam.area!=null)ok=this.tankSend(body,"laser",tune.laserPower) && ok;
        }
    }
    return true;
};
tankFinishAttack=function(body:MovieClip):Void {
    if(!this.tankCanAct(body))return;
    this.tankCancelAttack();
    this.tankReadyAt=this.tankClock+this.tankTuning.recoveryFrames;
    this.动画完毕();
};
tankBeginDeath=function(body:MovieClip):Void {
    this.tankCancelAttack();
    this.tankDeathStarted=true;
    body.tankIdentity=this.tankIdentity;
    body.tankWorldIdentity=this.tankWorldIdentity;
    body.stop();
};
tankBurstDeath=function(body:MovieClip):Void {
    if(_root.暂停 || body!==this.man || body.tankIdentity!==this.tankIdentity
        || !this.tankWorldValid() || !(this.hp<=0) || this.tankDeathSpent)return;
    this.tankDeathSpent=true;
    if(this.tankTuning.deathPower>0){
        var point:MovieClip=this.tankArea(body,530.35,630,680,420);
        if(point.area!=null){
            var world:MovieClip=_root.gameworld;
            var pos:Object={x:0,y:0};
            point.localToGlobal(pos);world.globalToLocal(pos);
            _root.子弹区域shoot传递({声音:"",霰弹值:1,子弹散射度:0,发射效果:"",
                子弹种类:"近战子弹",子弹威力:this.空手攻击力*this.tankTuning.deathPower,
                子弹速度:0,Z轴攻击范围:80,发射者:this._name,产生源:this._name,
                shootX:pos.x,shootY:pos.y,shootZ:this.Z轴坐标,命中率:100,
                击倒率:1,水平击退速度:14,垂直击退速度:-6,
                击中后子弹的效果:"火花",击中地图效果:"",
                区域定位area:point.area,伤害类型:"物理",
                cf2TankAction:"death",cf2TankKind:"deathBurst"});
        }
    }
    _root.播放音效("CF6_1009.mp3");
    _root.效果("火花",this._x,this._y-100,this._xscale*1.4);
    _root.效果("小烟雾",this._x,this._y-100,this._xscale*1.4);
};
tankStartFragments=function(scope:MovieClip,count:Number):Void {
    if(scope.tankStarted===true || this.hp>0 || !this.tankWorldValid())return;
    scope.tankStarted=true;
    for(var fi:Number=1;fi<=count;fi++){
        var fragment:MovieClip=scope["碎片"+fi];
        if(fragment.piece!=null){
            var bounds:Object=fragment.getBounds(fragment);
            var cx:Number=(bounds.xMin+bounds.xMax)/2,cy:Number=(bounds.yMin+bounds.yMax)/2;
            fragment.piece._x-=cx;fragment.piece._y-=cy;
            fragment._x+=cx;fragment._y+=cy;
        }
    }
    var ground:Object={x:0,y:0};this.localToGlobal(ground);scope.globalToLocal(ground);
    var identity:Object={},worldIdentity:Object=this.tankWorldIdentity;
    scope.tankIdentity=identity;scope.tankSettled=false;
    var id:Number=_root.地图元件.地图元件破碎动画(scope,"碎片",{fragmentCount:count,
        groundY:ground.y,gravity:1.5,bounce:0.18,friction:0.65,stopThresholdBase:1.25,
        baseVelocityX:2,velocityXRange:5,velocityYMin:3,velocityYMax:7,rotationRange:10,collisionProbability:0});
    scope.tankEngineStep=scope.onEnterFrame;
    scope.onUnload=function():Void {_root.地图元件.停止地图元件破碎动画(id);};
    scope.onEnterFrame=function():Void {
        if(this.tankIdentity!==identity)return;
        if(_root.gameworld.__cf2TankWorldIdentity!==worldIdentity){
            _root.地图元件.停止地图元件破碎动画(id);delete this.onEnterFrame;return;
        }
        if(_root.暂停)return;
        if(typeof this.tankEngineStep!="function" || !(id>=0))return;
        this.tankEngineStep.call(this);
        if(!_root.地图元件.地图元件破碎动画运行中(id)){
            this.tankSettled=true;delete this.tankEngineStep;delete this.onEnterFrame;
        }
    };
};
tankSyncArt=function(body:MovieClip):Void {
    body.tankPort_gun._visible=false;
    body.tankPort_cannon._visible=false;
    body.tankPort_beam._visible=false;
    body.tankPort_grenade._visible=false;
    body.tankContact._visible=false;
    var art:MovieClip=body.tankArt;
    if(art==null)return;
    var frame:Number=body.tankArtStart+body._currentframe-1;
    art.gotoAndStop(frame);
};
tankBodyTick=function(body:MovieClip,identity:Object):Void {
    if(_root.暂停 || body!==this.man || !this.tankWorldValid()
        || identity!==body.tankFrameIdentity)return;
    this.tankSyncArt(body);
    if(body.tankMode=="death"){
        if(body.tankIdentity!==this.tankIdentity || this.hp>0)return;
        if(body._currentframe<body._totalframes)body.nextFrame();
        else if(body.尸体碎片.tankSettled===true && !this.tankDeathFinished){
            this.tankDeathFinished=true;this.tankShadow._visible=false;this.死亡检测();
        }
        return;
    }
    if(body.tankMode=="hit"){
        if(body._currentframe<body._totalframes){body.nextFrame();this.tankSyncArt(body);}else this.动画完毕();
        return;
    }
    if(body.tankMode!="attack"){
        if(body._currentframe<body._totalframes)body.nextFrame();else body.gotoAndStop(1);
        this.tankSyncArt(body);
        return;
    }
    if(!this.tankCanAct(body))return;
    var owner:Object=this.tankOwner;
    if(!this.tankStrike(body))return;
    if(!this.tankCanAct(body))return;
    var f:Number=body._currentframe;
    if(owner.action=="mobile" && owner.lastMovePulse!=owner.pulse
        && owner.moved<this.tankTuning.maximumMove){
        var rawSpeed:Number=(f>=owner.spec.loopStart && f<=owner.spec.loopEnd)
            ?this.tankTuning.moveSpeed
            :(owner.spec.brakeHit!=null && f>owner.spec.loopEnd && f<owner.spec.brakeHit
                ?this.tankTuning.brakeSpeed:0);
        if(rawSpeed>0){
            var step:Number=Math.min(rawSpeed,this.tankTuning.maximumMove-owner.moved);
            var before:Number=this._x;
            this.移动(owner.direction,step);
            owner.moved+=Math.abs(this._x-before);
            owner.lastMovePulse=owner.pulse;
        }
    }
    owner.pulse++;
    if(owner.spec.loopEnd==f && owner.loops<this.tankTuning.loops){
        owner.loops++;body.gotoAndStop(owner.spec.loopStart);this.tankSyncArt(body);return;
    }
    if(f<body._totalframes){body.nextFrame();this.tankSyncArt(body);}else this.tankFinishAttack(body);
};
tankChoose=function(forwardDx:Number,adz:Number):String {
    var t:Object=this.tankTuning,next:Object=this.tankNext,clock:Number=this.tankClock;
    if(isNaN(forwardDx) || isNaN(adz) || adz<0 || adz>t.laneRange
        || clock<this.tankReadyAt)return "";
    if(forwardDx<0){
        var rearDist:Number=-forwardDx;
        if(rearDist<=t.rearMeleeRange && !(next.melee>clock))return "melee";
        if(rearDist<=t.rearGunRange && !(next.gatling>clock))return "gatling";
        return "";
    }
    if(forwardDx<t.meleeRange && !(next.melee>clock))return "melee";
    if(forwardDx>=t.barrageMinRange && forwardDx<t.gunRange){
        if(!(next.mobile>clock) && (this.tankAttackSequence%2)==1)return "mobile";
        if(!(next.barrage>clock))return "barrage";
    }
    if(forwardDx<t.laserRange && !(next.laser>clock))return "laser";
    return "";
};
tankAttackSequence=0;
tankUpdateShadow=function():Void {
    var shadow:MovieClip=this.tankShadow;
    shadow._visible=_root.是否阴影===true;
    if(isNaN(this.Z轴坐标))return;
    var point:Object=this.tankGroundPoint;
    point.x=this._x;point.y=this.Z轴坐标;
    this._parent.localToGlobal(point);this.globalToLocal(point);
    shadow._x=point.x;shadow._y=point.y;
    shadow._rotation=this._xscale<0?this._rotation:-this._rotation;
};
tankTick=function(identity:Object):Void {
    if(_root.暂停 || !this.tankWorldValid())return;
    if(identity!==undefined && identity!==this.tankIdentity)return;
    if(isNaN(this.hp))return;
    this.area._visible=false;
    this.tankUpdateShadow();
    this.tankClock++;
    if(this.hp<=0){
        this.tankCancelAttack();
        if(this.状态!="血腥死" && this.状态!="消失")this.状态改变("血腥死");
        return;
    }
    var owner:Object=this.tankOwner;
    if(owner!=null){
        if(this.状态!=owner.state || this.man.tankToken!==owner.token)this.tankCancelAttack();
        return;
    }
    if(this.硬直中 || this.tankClock<this.tankReadyAt)return;
    if(_root.控制目标==this._name && _root.控制目标全自动!==true)return;
    if(this.状态!="空手站立" && this.状态!="空手行走" && this.状态!="空手跑")return;
    var target:MovieClip=_root.gameworld[this.攻击目标];
    if(!(target.hp>0) || target._parent!==this._parent)return;
    this.x轴攻击范围=0;if(this.unitAI.data!=null)this.unitAI.data.xrange=0;
    var dx:Number=target._x-this._x,dz:Number=target.Z轴坐标-this.Z轴坐标;
    if(isNaN(dx) || isNaN(dz))return;
    if(Math.abs(target._y-target.Z轴坐标)>this.tankTuning.maximumTargetHeight)return;
    var adx:Number=Math.abs(dx),adz:Number=Math.abs(dz);
    var forwardDx:Number=this.方向=="左"?-dx:dx;
    var action:String=this.tankChoose(forwardDx,adz);
    if(action!=""){
        this.tankAttackSequence++;
        this.状态改变(this.tankActions[action].state);return;
    }
    var desiredFace:String=dx<0?"左":"右";
    if(forwardDx<-this.tankTuning.turnDeadzone
        && (this.tankClock-this.tankLastTurnAt)>=this.tankTuning.turnCooldown){
        this.方向改变(desiredFace);this.tankLastTurnAt=this.tankClock;
    }
    if(adz>this.tankTuning.laneRange*0.65){
        if(this.状态!="空手行走" && this.状态!="空手跑")this.状态改变("空手行走");
        this.移动(dz<0?"上":"下",Math.min(this.行走Y速度,adz));return;
    }
    if(this.方向==desiredFace && adx>this.tankTuning.keepDistance){
        if(this.状态!="空手行走" && this.状态!="空手跑")this.状态改变("空手行走");
        this.移动(this.方向,Math.min(this.行走X速度,adx-this.tankTuning.keepDistance));return;
    }
    if(this.状态=="空手行走" || this.状态=="空手跑")this.状态改变("空手站立");
};
