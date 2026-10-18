// 两种机械尸体共用的小型表现适配。碎片仍由地图破碎动画计算，伤害和击杀保持原入口。
cf6StartCorpseFragments=function(scope:MovieClip,count:Number):Void {
    if(scope.cf6Started===true)return;scope.cf6Started=true;
    var ground:Object={x:0,y:0};this.localToGlobal(ground);scope.globalToLocal(ground);
    var world:MovieClip=_root.gameworld;
    if(world.__cf6CorpseWorldIdentity==undefined)world.__cf6CorpseWorldIdentity={};
    scope.cf6WorldIdentity=world.__cf6CorpseWorldIdentity;
    // 静止阈值覆盖落地后单帧重力反弹，避免不同碎片交替微弹而永不结束。
    scope.cf6AnimationId=_root.地图元件.地图元件破碎动画(scope,"碎片",{fragmentCount:count,
        groundY:ground.y,gravity:1.5,bounce:0.22,friction:0.65,stopThresholdBase:1.25,baseVelocityX:2,velocityXRange:5,
        velocityYMin:3,velocityYMax:7,rotationRange:12,collisionProbability:0,enableDebug:false});
    var fragmentIdentity:Object={};scope.cf6Identity=fragmentIdentity;
    var ownedAnimationId:Number=scope.cf6AnimationId;
    scope.cf6EngineStep=scope.onEnterFrame;
    scope.cf6Settled=false;
    scope.onUnload=function():Void {
        _root.地图元件.停止地图元件破碎动画(ownedAnimationId);
        if(this.cf6Identity!==fragmentIdentity)return;
        delete this.cf6EngineStep;
    };
    if(!(scope.cf6AnimationId>=0) || typeof scope.cf6EngineStep!="function"){
        trace("[CF6_CORPSE_ERROR] fragment engine unavailable "+this._name);return;
    }
    scope.onEnterFrame=function():Void {
        if(this.cf6Identity!==fragmentIdentity || this.cf6Settled===true)return;
        if(_root.gameworld.__cf6CorpseWorldIdentity!==this.cf6WorldIdentity){
            _root.地图元件.停止地图元件破碎动画(ownedAnimationId);
            delete this.cf6EngineStep;delete this.onEnterFrame;return;
        }
        if(_root.暂停)return;
        this.cf6EngineStep.call(this);
        if(!_root.地图元件.地图元件破碎动画运行中(ownedAnimationId)){
            this.cf6Settled=true;delete this.cf6EngineStep;delete this.onEnterFrame;
        }
    };
};
cf6FinishCorpse=function(body:MovieClip):Void {
    if(body!==this.man || this.hp>0 || _root.暂停 || body.cf6CorpseFinished===true)return;
    if(body.尸体碎片==null || body.尸体碎片.cf6Settled!==true)return;
    body.cf6CorpseFinished=true;
    if(body.headbotShadow!=null)body.headbotShadow._visible=false;
    if(body.elderShadow!=null)body.elderShadow._visible=false;
    this.死亡检测();
};
