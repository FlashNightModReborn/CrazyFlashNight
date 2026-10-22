// 蛮蛮私有控制：借用不死兽人动作与正式近战判定，限定本单位的追击和收招节奏。
// baseline 只供隔离对照：保留通用近身攻击及兽人的前方重击触发方式。
if (_arenaCalibrationUnit !== true || (蛮蛮AI模式 != "baseline" && 蛮蛮AI模式 != "enhanced")) {
    蛮蛮AI模式 = "enhanced";
}
manmanClock = 0;
manmanReadyAt = 8;
manmanNextAdvance = 0;
manmanNextWolf = 0;
manmanTargetName = "";
manmanAttackOwner = null;
manmanDecisionCount = 0;
manmanAttackCount = 0;
manmanHitCount = 0;
manmanTuning = {cleaveRange:100, advanceRange:200, laneRange:22, keepDistance:75,
    reactionFrames:8, recoveryFrames:0, advanceCooldown:40, maximumTargetHeight:65,
    crumblePercent:0.25, wolfMinRange:200, wolfRange:440, wolfLaneRange:72,
    wolfDepthLimit:60, wolfTravelLimit:360, wolfStandOff:70, wolfCooldown:180,
    wolfWindup:18, wolfFlight:12, wolfImpactFrame:31, wolfHeight:90};
// 仅隔离实战允许关闭击溃，以保持动作、AI 和面板不变地做对照。
manmanCrumblePercent = (_arenaCalibrationUnit === true && 蛮蛮击溃模式 == "off")
    ? 0 : manmanTuning.crumblePercent;

// 影子独立于身体关节，始终投到当前纵深的地面。
manmanSyncWolfShadow = function(body:MovieClip):Void {
    var shadow:MovieClip = body.wolfShadow;
    if (shadow == null) return;
    shadow._visible = _root.是否阴影 == true;
    var point:Object = body.manmanShadowPoint;
    if (point == null) point = body.manmanShadowPoint = {};
    point.x = this._x; point.y = this.Z轴坐标;
    this._parent.localToGlobal(point);
    body.globalToLocal(point);
    // 原站姿影子在单位局部坐标 (-3.5, -0.35)；坐标转换兼容身高缩放。
    shadow._x = point.x - 3.5;
    shadow._y = point.y - 0.35;
};

// _y 按 twip 存储；落地时消除分段纵移与 sin(PI) 的浮点尾差。
manmanLandWolf = function():Void {
    this.Z轴坐标 = Math.round(this.Z轴坐标 * 20) / 20;
    this._y = this.Z轴坐标;
    this.manmanSyncWolfShadow(this.man);
    if (this.aabbCollider != null) this.aabbCollider.updateFromUnitArea(this);
};

manmanCancelAttack = function():Void {
    var owner:Object = this.manmanAttackOwner;
    if (owner == null) return;
    owner.active = false;
    if (owner.ownsRigid) this.刚体 = owner.previousRigid;
    // 只回收本动作仍持有的演出高度，不覆盖外部击飞已经写入的位置。
    if (owner.action == "wolf" && owner.ownsLift && this._y === owner.lastLiftY) {
        this.manmanLandWolf();
    }
    if (owner.action == "wolf") this.manmanSyncWolfShadow(this.man);
    this.manmanAttackOwner = null;
};

manmanExpectedState = function(action:String):String {
    return action == "wolf" ? "狼跳" : action == "advance" ? "近战" : "空手攻击";
};

manmanBeginAttack = function(body:MovieClip, action:String):Void {
    this.manmanCancelAttack();
    if (!(this.hp > 0)) { body.stop(); return; }
    var token:Object = {};
    body.manmanToken = token;
    this.manmanAttackOwner = {token:token, action:action, active:true,
        previousRigid:this.刚体 === true, ownsRigid:false};
    this.manmanAttackCount++;
    if (action == "advance") this.manmanNextAdvance = this.manmanClock + this.manmanTuning.advanceCooldown;
    if (action == "wolf") {
        this.manmanPrepareWolf();
        this.manmanSyncWolfShadow(body);
    }
};

manmanCanHit = function(token:Object):Boolean {
    var owner:Object = this.manmanAttackOwner;
    return !_root.暂停 && this.hp > 0 && owner != null && owner.active && owner.token === token
        && this.man.manmanToken === token
        && this.状态 == this.manmanExpectedState(owner.action);
};

// 在蓄势开始时固定目标坐标；此后不读取目标，横移/绕后可以使它落空。
manmanPrepareWolf = function():Void {
    var owner:Object = this.manmanAttackOwner;
    var tune:Object = this.manmanTuning;
    var target:MovieClip = _root.gameworld[this.攻击目标];
    var face:Number = this.方向 == "左" ? -1 : 1;
    var distance:Number = (target._x - this._x) * face - tune.wolfStandOff;
    var depth:Number = target.Z轴坐标 - this.Z轴坐标;
    if (isNaN(distance) || isNaN(depth)) { distance = 0; depth = 0; }
    distance = distance < 0 ? 0 : distance > tune.wolfTravelLimit ? tune.wolfTravelLimit : distance;
    depth = depth < -tune.wolfDepthLimit ? -tune.wolfDepthLimit : depth > tune.wolfDepthLimit ? tune.wolfDepthLimit : depth;
    owner.startX = this._x; owner.startZ = this.Z轴坐标;
    owner.travelX = distance * face; owner.travelZ = depth;
    owner.lastFrame = 0; owner.progress = 0; owner.hit = false; owner.ownsLift = false;
    this.manmanNextWolf = this.manmanClock + tune.wolfCooldown;
    if (this._arenaCalibrationUnit === true) _root.服务器.发布服务器消息("[MANMAN_WOLF] event=begin unit="+this._name+" x="+this._x+" z="+this.Z轴坐标+" travelX="+owner.travelX+" travelZ="+owner.travelZ);
};

// 沿正式碰撞移动出口小步推进；被墙挡住时不在后续帧补偿成瞬移。
manmanWolfMove = function(direction:String, distance:Number):Void {
    var remaining:Number = distance > 32 ? 32 : distance;
    while (remaining > 0) {
        var step:Number = remaining > 4 ? 4 : remaining;
        var x:Number = this._x, z:Number = this.Z轴坐标;
        this.移动(direction, step);
        if (x === this._x && z === this.Z轴坐标) return;
        remaining -= step;
    }
};

manmanWolfStep = function(body:MovieClip):Void {
    if (!this.manmanCanHit(body.manmanToken)) return;
    var owner:Object = this.manmanAttackOwner;
    if (owner.action != "wolf") return;
    var frame:Number = body._currentframe;
    if (frame === owner.lastFrame) { this.manmanSyncWolfShadow(body); return; }
    owner.lastFrame = frame;
    var tune:Object = this.manmanTuning;
    if (frame > tune.wolfWindup && frame <= tune.wolfImpactFrame) {
        var progress:Number = (frame - tune.wolfWindup) / tune.wolfFlight;
        if (progress > 1) progress = 1;
        var delta:Number = progress - owner.progress;
        owner.progress = progress;
        var dx:Number = owner.travelX * delta;
        var dz:Number = owner.travelZ * delta;
        this.manmanWolfMove(dx < 0 ? "左" : "右", dx < 0 ? -dx : dx);
        this.manmanWolfMove(dz < 0 ? "上" : "下", dz < 0 ? -dz : dz);
        if (progress < 1) this._y = this.Z轴坐标 - Math.sin(progress * Math.PI) * tune.wolfHeight;
        else this.manmanLandWolf();
        owner.ownsLift = progress < 1; owner.lastLiftY = this._y;
        if (this.aabbCollider != null) this.aabbCollider.updateFromUnitArea(this);
    } else if (frame >= tune.wolfImpactFrame && owner.ownsLift) {
        this.manmanLandWolf(); owner.ownsLift = false;
    }
    this.manmanSyncWolfShadow(body);
};

manmanWolfImpact = function(body:MovieClip):Void {
    if (!this.manmanCanHit(body.manmanToken)) return;
    var owner:Object = this.manmanAttackOwner;
    // 刚体仍可能带移动钝感硬直；真正中断由状态/token 判定，与原斧击一致。
    if (owner.action != "wolf" || owner.hit
        || body._currentframe !== this.manmanTuning.wolfImpactFrame) return;
    this.manmanWolfStep(body);
    owner.hit = true;
    this.manmanHitCount++;
    var point:Object = {x:90, y:5};
    body.localToGlobal(point); _root.gameworld.globalToLocal(point);
    _root.子弹区域shoot传递({声音:"", 霰弹值:1, 子弹散射度:0, 发射效果:"",
        子弹种类:"近战子弹", 子弹威力:this.空手攻击力, 子弹速度:0,
        Z轴攻击范围:36, 击中地图效果:"", 发射者:this._name,
        shootX:point.x, shootY:point.y, shootZ:this.Z轴坐标,
        子弹敌我属性:this.是否为敌人 !== true, 击倒率:1, 击中后子弹的效果:"空手攻击火花",
        血量上限击溃:this.manmanCrumblePercent, 区域定位area:body.wolfHit.area});
    if (this._arenaCalibrationUnit === true) _root.服务器.发布服务器消息("[MANMAN_WOLF] event=impact unit="+this._name+" frame="+body._currentframe+" x="+this._x+" z="+this.Z轴坐标+" height="+(this.Z轴坐标-this._y)+" rigid="+this.刚体+" stiff="+this.硬直中);
    _root.播放音效("CF6_0655.mp3");
};

manmanAnimationDone = function(body:MovieClip):Void {
    var owner:Object = this.manmanAttackOwner;
    if (owner == null || owner.token !== body.manmanToken) return;
    if (owner.action == "wolf" && this._arenaCalibrationUnit === true) _root.服务器.发布服务器消息("[MANMAN_WOLF] event=recovered unit="+this._name+" frame="+body._currentframe);
    this.manmanCancelAttack();
    this.manmanReadyAt = this.manmanClock + this.manmanTuning.recoveryFrames;
    this.动画完毕();
};

manmanChooseAttack = function(dx:Number, dz:Number, height:Number):String {
    if (isNaN(dx) || isNaN(dz) || isNaN(height) || dx < 0 || dz < 0) return "none";
    var tune:Object = this.manmanTuning;
    if (height > tune.maximumTargetHeight || this.manmanClock < this.manmanReadyAt) return "none";
    if (dx > tune.wolfMinRange && dx <= tune.wolfRange && dz <= tune.wolfLaneRange
        && this.manmanClock >= this.manmanNextWolf) return "wolf";
    if (dz > tune.laneRange) return "none";
    if (dx <= tune.cleaveRange) return "cleave";
    if (dx <= tune.advanceRange && this.manmanClock >= this.manmanNextAdvance) return "advance";
    return "none";
};

manmanTick = function():Void {
    if (_root.暂停) return;
    this.manmanClock++;
    // 致死伤害可能发生在发力前；取消攻击后仍必须进入死亡流程。
    if (!isNaN(this.hp) && this.hp <= 0) {
        this.manmanCancelAttack();
        if (this.状态 != "血腥死" && this.状态 != "消失") this.状态改变("血腥死");
        return;
    }
    var owner:Object = this.manmanAttackOwner;
    if (owner != null) {
        var expected:String = this.manmanExpectedState(owner.action);
        if (!(this.hp > 0) || this.状态 != expected || this.man.manmanToken !== owner.token) {
            this.manmanCancelAttack();
        } else {
            // 只在发力段持有刚体；保留起手与收招的反击窗口。
            var body:MovieClip = this.man;
            var active:Boolean = owner.action == "wolf"
                ? body._currentframe > this.manmanTuning.wolfWindup && body._currentframe <= this.manmanTuning.wolfImpactFrame
                : body._currentframe >= 8 && body._currentframe <= 17;
            if (owner.action == "wolf") this.manmanWolfStep(body);
            if (active && !owner.ownsRigid) {
                owner.previousRigid = this.刚体 === true;
                owner.ownsRigid = true;
                this.刚体 = true;
            } else if (!active && owner.ownsRigid) {
                this.刚体 = owner.previousRigid;
                owner.ownsRigid = false;
            }
        }
    }
    if (!(this.hp > 0) || this.倒地 || this.浮空 || this.硬直中) return;
    if (_root.控制目标 == this._name && _root.控制目标全自动 == false) return;
    if (this.状态 != "空手站立" && this.状态 != "空手行走" && this.状态 != "空手跑") return;
    if ((this.manmanClock & 3) != 0) return;
    var target:MovieClip = _root.gameworld[this.攻击目标];
    if (!(target.hp > 0) || target == this || target.area == null) return;
    var dx:Number = target._x - this._x;
    var dz:Number = target.Z轴坐标 - this.Z轴坐标;
    var height:Number = target.Z轴坐标 - target._y;
    if (isNaN(dx) || isNaN(dz) || isNaN(height)) return;
    this.manmanDecisionCount++;
    if (this.蛮蛮AI模式 == "baseline") {
        if (Math.abs(dz) <= this.y轴攻击范围 && this.manmanSensor.hitTest(target.area)
            && this.manmanClock >= this.manmanReadyAt) {
            this.近战招式 = "a0";
            this.状态改变("近战");
        }
        return;
    }
    // 通用 AI 继续管理仇恨；本单位独占自动攻击，且同步其缓存的距离参数。
    this.x轴攻击范围 = 0;
    this.y轴攻击范围 = this.manmanTuning.laneRange;
    this.x轴保持距离 = this.manmanTuning.keepDistance;
    if (this.unitAI.data != null) {
        this.unitAI.data.xrange = 0;
        this.unitAI.data.zrange = this.y轴攻击范围;
        this.unitAI.data.xdistance = this.x轴保持距离;
    }
    if (this.manmanTargetName != target._name) {
        this.manmanTargetName = target._name;
        this.manmanReadyAt = this.manmanClock + this.manmanTuning.reactionFrames;
    }
    var move:String = this.manmanChooseAttack(Math.abs(dx), Math.abs(dz), height);
    if (move == "none") {
        // 纵深未对齐或突进仍冷却时继续接近，避免停在自己打不到的位置。
        this.上行 = dz < -6;
        this.下行 = dz > 6;
        this.左行 = dx < -this.manmanTuning.keepDistance;
        this.右行 = dx > this.manmanTuning.keepDistance;
        if (Math.abs(dx) > 230 && this.状态 != "空手跑") this.状态改变("空手跑");
        return;
    }
    this.左行 = this.右行 = this.上行 = this.下行 = false;
    if (dx < 0) this.方向改变("左");
    else if (dx > 0) this.方向改变("右");
    this.近战招式 = "a0";
    this.状态改变(this.manmanExpectedState(move));
};

if (蛮蛮AI模式 == "enhanced") {
    x轴攻击范围 = 0;
    y轴攻击范围 = manmanTuning.laneRange;
    x轴保持距离 = manmanTuning.keepDistance;
    if (unitAI.data != null) {
        unitAI.data.xrange = 0;
        unitAI.data.zrange = y轴攻击范围;
        unitAI.data.xdistance = x轴保持距离;
    }
}
