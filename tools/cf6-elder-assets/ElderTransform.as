// 老头默认连续两阶段；关卡可显式传 false 使用独立人形。
if(老头变身==undefined)老头变身=true;
else if(老头变身===true || 老头变身===1 || 老头变身==="true" || 老头变身==="1")老头变身=true;
else if(老头变身===false || 老头变身===0 || 老头变身==="false" || 老头变身==="0")老头变身=false;
else {trace("[CF6_ELDER_CONFIG_ERROR] invalid 老头变身="+老头变身);老头变身=false;}
if(老头变身===true)不掉钱=true;
elderTransform=null;
elderStartTransform=function():Void {
    if(this.elderTransform!=null || this.老头变身!==true || !(this.hp<=0))return;
    this.elderReportCombat();this.elderCancelAttack();this.elderClearMovement();
    var world:MovieClip=this._parent;
    if(world.__elderWorldIdentity==undefined)world.__elderWorldIdentity={};
    this.elderTransform={active:true,attempted:false,retired:false,waitFrames:0,
        world:world,worldIdentity:world.__elderWorldIdentity,parentIdentity:this.elderIdentity,spawnIdentity:{},
        name:this._name+"__elderbot",level:this.等级,side:this.是否为敌人,source:this.产生源,
        direction:this.方向,x:this._x,z:this.Z轴坐标,target:this.攻击目标};
    this.浮空=this.倒地=false;this.水平速度=this.垂直速度=this.speed=0;
    this._y=this.Z轴坐标;this._rotation=0;
    this.状态="变身";this.gotoAndStop("变身");
};
elderBeginTransform=function(body:MovieClip):Void {
    body.stop();
    var phase:Object=this.elderTransform;
    if(phase==null || !phase.active || this.man!==body)return;
    phase.body=body;body.elderPhaseIdentity=phase.spawnIdentity;
};
elderTransformError=function(reason:String):Void {
    var phase:Object=this.elderTransform;
    if(phase==null || phase.error!=undefined)return;
    phase.error=reason;phase.active=false;
    trace("[CF6_ELDER_TRANSFORM_ERROR] "+this._name+" "+reason);
};
elderPhaseValid=function(body:MovieClip):Boolean {
    var phase:Object=this.elderTransform;
    return phase!=null && phase.active && !phase.retired && this.man===body && phase.body===body
        && body.elderPhaseIdentity===phase.spawnIdentity && this.elderIdentity===phase.parentIdentity
        && phase.world===_root.gameworld && phase.world.__elderWorldIdentity===phase.worldIdentity;
};
elderSpawnRobot=function(body:MovieClip):Void {
    var phase:Object=this.elderTransform;
    if(_root.暂停 || !this.elderPhaseValid(body) || phase.attempted || body._currentframe!=93)return;
    // 返回为空或初始化超时都保留已尝试身份，禁止自动重放生成。
    phase.attempted=true;
    if(phase.world[phase.name]!=undefined){this.elderTransformError("successor-name-conflict");return;}
    var params:Object={_x:phase.x,_y:phase.z,等级:phase.level,是否为敌人:phase.side,
        身高:190,产生源:phase.source,名字:"老头机器人",_visible:false,elderSpawnIdentity:phase.spawnIdentity};
    phase.child=_root.加载游戏世界人物("敌人-CF6老头机器人",phase.name,phase.world.getNextHighestDepth(),params);
    if(phase.child==null)this.elderTransformError("spawn-returned-empty");
};
elderTransformTick=function(body:MovieClip):Void {
    var phase:Object=this.elderTransform;
    if(_root.暂停 || phase==null || !phase.active || phase.retired || this.状态!="变身")return;
    if(!this.elderPhaseValid(body)){this.elderTransformError("phase-identity-lost");return;}
    if(!phase.attempted){
        if(body._currentframe==93)this.elderSpawnRobot(body);else body.nextFrame();
        return;
    }
    var child:MovieClip=phase.child;
    if(child._parent!==phase.world || child._name!=phase.name || phase.world[phase.name]!==child
        || child.elderSpawnIdentity!==phase.spawnIdentity){this.elderTransformError("successor-identity-lost");return;}
    phase.waitFrames++;
    if(child.__unitInitializedVersion!=null && child.__unitInitializedVersion===child.version
        && child.兵种=="敌人-CF6老头机器人" && child.hp满血值>0 && !isNaN(child.hp)){
        if(child.等级!=phase.level || child.是否为敌人!==phase.side){this.elderTransformError("successor-context-mismatch");return;}
        phase.successorInitialized={level:child.等级,maxHp:child.hp满血值,attack:child.空手攻击力,defense:child.防御力};
        var diagnostic:String="[CF6_ELDER_PHASE_READY] parent="+this._name+" child="+child._name
            +" level="+child.等级+" maxHp="+child.hp满血值+" hp="+child.hp
            +" attack="+child.空手攻击力+" defense="+child.防御力+" enemy="+child.是否为敌人;
        trace(diagnostic);
        if(typeof _root.服务器.发布服务器消息=="function")_root.服务器.发布服务器消息(diagnostic);
        child.方向改变(phase.direction);child._visible=true;
        var target:MovieClip=phase.world[phase.target];
        if(target.hp>0 && target.是否为敌人!==child.是否为敌人)child.攻击目标=phase.target;
        phase.retired=true;phase.active=false;
        this.死亡检测({noCount:true,noCorpse:true});
    }else if(phase.waitFrames>=30)this.elderTransformError("successor-initialization-timeout");
};
