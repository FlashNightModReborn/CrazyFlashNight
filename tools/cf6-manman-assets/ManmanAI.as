// 蛮蛮私有控制：借用不死兽人动作与正式近战判定，限定本单位的追击和收招节奏。
// baseline 只供隔离对照：保留通用近身攻击及兽人的前方重击触发方式。
if (_arenaCalibrationUnit !== true || (蛮蛮AI模式 != "baseline" && 蛮蛮AI模式 != "enhanced")) {
    蛮蛮AI模式 = "enhanced";
}
manmanClock = 0;
manmanReadyAt = 8;
manmanNextAdvance = 0;
manmanTargetName = "";
manmanAttackOwner = null;
manmanDecisionCount = 0;
manmanAttackCount = 0;
manmanHitCount = 0;
manmanTuning = {cleaveRange:100, advanceRange:200, laneRange:22, keepDistance:75,
    reactionFrames:8, recoveryFrames:0, advanceCooldown:40, maximumTargetHeight:65,
    crumblePercent:0.25};
// 仅隔离实战允许关闭击溃，以保持动作、AI 和面板不变地做对照。
manmanCrumblePercent = (_arenaCalibrationUnit === true && 蛮蛮击溃模式 == "off")
    ? 0 : manmanTuning.crumblePercent;

manmanCancelAttack = function():Void {
    var owner:Object = this.manmanAttackOwner;
    if (owner == null) return;
    owner.active = false;
    if (owner.ownsRigid) this.刚体 = owner.previousRigid;
    this.manmanAttackOwner = null;
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
};

manmanCanHit = function(token:Object):Boolean {
    var owner:Object = this.manmanAttackOwner;
    return !_root.暂停 && this.hp > 0 && owner != null && owner.active && owner.token === token
        && this.man.manmanToken === token
        && this.状态 == (owner.action == "advance" ? "近战" : "空手攻击");
};

manmanAnimationDone = function(body:MovieClip):Void {
    var owner:Object = this.manmanAttackOwner;
    if (owner == null || owner.token !== body.manmanToken) return;
    this.manmanCancelAttack();
    this.manmanReadyAt = this.manmanClock + this.manmanTuning.recoveryFrames;
    this.动画完毕();
};

manmanChooseAttack = function(dx:Number, dz:Number, height:Number):String {
    if (isNaN(dx) || isNaN(dz) || isNaN(height) || dx < 0 || dz < 0) return "none";
    var tune:Object = this.manmanTuning;
    if (dz > tune.laneRange || height > tune.maximumTargetHeight || this.manmanClock < this.manmanReadyAt) return "none";
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
        var expected:String = owner.action == "advance" ? "近战" : "空手攻击";
        if (!(this.hp > 0) || this.状态 != expected || this.man.manmanToken !== owner.token) {
            this.manmanCancelAttack();
        } else {
            // 只在发力段持有刚体；保留起手与收招的反击窗口。
            var active:Boolean = this.man._currentframe >= 8 && this.man._currentframe <= 17;
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
    this.状态改变(move == "advance" ? "近战" : "空手攻击");
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
