// 第一阶段死亡后只尝试生成一次全新暴君；关卡人数由后继单位死亡时结算。
if(光头保安变身==undefined)光头保安变身=true;
if(光头保安变身!==false)不掉钱=true;
guardTransform=null;

guardStartTransform=function():Void {
    if(this.guardTransform!=null || this.光头保安变身===false || !(this.hp<=0))return;
    this.guardCancelAttack();this.guardClearMovement();
    this.guardTransform={active:true,attempted:false,retired:false,waitFrames:0,
        world:this._parent,name:this._name+"__tyrant",level:this.等级,
        side:this.是否为敌人,source:this.产生源,direction:this.方向,x:this._x,z:this.Z轴坐标};
    this.浮空=this.倒地=false;this.水平速度=this.垂直速度=0;
    this._y=this.Z轴坐标;this._rotation=0;
    this.状态="变身";this.gotoAndStop("变身");
};

guardBeginTransform=function(body:MovieClip):Void {
    body.stop();
    var phase:Object=this.guardTransform;
    if(phase==null || !phase.active || this.man!==body)return;
    phase.body=body;
};

guardTransformError=function(reason:String):Void {
    var phase:Object=this.guardTransform;
    if(phase==null || phase.error!=undefined)return;
    phase.error=reason;phase.active=false;
    trace("[CF6_GUARD_TRANSFORM_ERROR] "+this._name+" "+reason);
};

guardSpawnTyrant=function(body:MovieClip):Void {
    var phase:Object=this.guardTransform;
    if(_root.暂停 || phase==null || !phase.active || phase.attempted || this.man!==body
        || phase.body!==body || body._currentframe!=70)return;
    // 先占有本次尝试；返回缺失或初始化超时均不得自动重放。
    phase.attempted=true;
    if(phase.world!==_root.gameworld || phase.world[phase.name]!=undefined){
        this.guardTransformError("world-or-name-conflict");return;
    }
    var params:Object={_x:phase.x,_y:phase.z,等级:phase.level,是否为敌人:phase.side,
        身高:230,产生源:phase.source,_visible:false};
    phase.child=_root.加载游戏世界人物("敌人-完全体克隆兽",phase.name,phase.world.getNextHighestDepth(),params);
    if(phase.child==null){this.guardTransformError("spawn-returned-empty");return;}
};

guardTransformTick=function(body:MovieClip):Void {
    var phase:Object=this.guardTransform;
    if(_root.暂停 || phase==null || !phase.active || phase.retired || phase.body!==body
        || this.man!==body || this.状态!="变身")return;
    if(!phase.attempted){body.nextFrame();return;}
    var child:MovieClip=phase.child;
    if(phase.world!==_root.gameworld || child._parent!==phase.world || child._name!=phase.name
        || phase.world[phase.name]!==child){this.guardTransformError("spawn-identity-lost");return;}
    phase.waitFrames++;
    if(child.__unitInitializedVersion!=null && child.__unitInitializedVersion===child.version
        && child.兵种=="敌人-完全体克隆兽" && child.hp>0){
        if(child.等级!=phase.level || child.是否为敌人!==phase.side){
            this.guardTransformError("successor-context-mismatch");return;
        }
        child.方向改变(phase.direction);child._visible=true;
        phase.retired=true;phase.active=false;
        // 与黑龙相同：第一阶段经验正常结算，人数保留给新单位；不留下重复尸体。
        this.死亡检测({noCount:true,noCorpse:true});
    }else if(phase.waitFrames>=30)this.guardTransformError("successor-initialization-timeout");
};
