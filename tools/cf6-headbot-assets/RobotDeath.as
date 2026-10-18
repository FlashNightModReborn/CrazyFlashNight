// 三种 CF6 机器人共用一次性亡语；视觉是私有矢量，声音走原生 SFX，伤害走正常子弹管线。
cf6RobotDeathIdentity={};cf6RobotDeathSpent=false;
cf6ArmRobotDeath=function(body:MovieClip,burstFrame:Number):Void {
    var world:MovieClip=_root.gameworld;
    if(world.__cf6RobotDeathWorldIdentity==undefined)world.__cf6RobotDeathWorldIdentity={};
    body.cf6RobotDeathIdentity=this.cf6RobotDeathIdentity;
    body.cf6RobotDeathWorldIdentity=world.__cf6RobotDeathWorldIdentity;
    body.cf6RobotDeathBurstFrame=burstFrame;
};
cf6RobotDeathTick=function(body:MovieClip):Boolean {
    if(_root.暂停 || body!==this.man || this._parent!==_root.gameworld
        || body.cf6RobotDeathIdentity!==this.cf6RobotDeathIdentity
        || body.cf6RobotDeathWorldIdentity!==_root.gameworld.__cf6RobotDeathWorldIdentity)return false;
    if(body._currentframe!=body.cf6RobotDeathBurstFrame || this.cf6RobotDeathSpent===true)return true;
    // 只画死亡姿态的预览不获得伤害授权。
    if(isNaN(this.hp) || this.hp>0)return true;
    var point:MovieClip=body.cf6DeathPoint;
    if(point.area==null || point._parent!==body || point.cf6RobotDeathIdentity!==this.cf6RobotDeathIdentity)return false;
    this.cf6RobotDeathSpent=true;
    var p:Object={x:point._x,y:point._y};body.localToGlobal(p);_root.gameworld.globalToLocal(p);
    _root.播放音效("CF6_1009.mp3");
    _root.子弹区域shoot传递({声音:"",霰弹值:1,子弹散射度:0,发射效果:"",子弹种类:"近战子弹",
        子弹威力:this.空手攻击力*2,子弹速度:0,Z轴攻击范围:80,击中地图效果:"",
        发射者:this._name,shootX:p.x,shootY:p.y,shootZ:this.Z轴坐标,击倒率:3,
        击中后子弹的效果:"火花",水平击退速度:8,垂直击退速度:0,
        区域定位area:point.area,伤害类型:"物理",cf6DeathBurst:true});
    return true;
};
