WingsAI模式 = (_arenaCalibrationUnit === true && WingsAI模式 == "baseline") ? "baseline" : "enhanced";
wingsClock = 0;
wingsReadyAt = 0;
wingsNextFlip = 0;
wingsNextCombo = 0;
wingsTargetName = "";
wingsAttackOwner = null;
wingsAttackCount = 0;
wingsHitCount = 0;
wingsInvalidMuzzleCount = 0;
wingsMuzzleRegistration = null;
wingsTuning = {shootRange:480, slashRange:115, comboRange:135, flipRange:230,
    laneRange:24, keepDistance:180, maximumTargetHeight:65,
    reactionFrames:6, recoveryFrames:2, flipCooldown:75, comboCooldown:55};

wingsCancelAttack = function():Void {
    if (this.wingsAttackOwner != null) this.wingsAttackOwner.active = false;
    this.wingsAttackOwner = null;
};

wingsBeginAttack = function(body:MovieClip, action:String):Void {
    this.wingsCancelAttack();
    if (!(this.hp > 0)) { body.stop(); return; }
    var token:Object = {};
    body.wingsToken = token;
    this.wingsAttackOwner = {token:token, action:action, active:true,
        state:action == "combo" ? "空手攻击" : "近战"};
    this.wingsAttackCount++;
    if (action == "flip") this.wingsNextFlip = this.wingsClock + this.wingsTuning.flipCooldown;
    if (action == "combo") this.wingsNextCombo = this.wingsClock + this.wingsTuning.comboCooldown;
};

wingsCanAct = function(body:MovieClip):Boolean {
    var owner:Object = this.wingsAttackOwner;
    return !_root.暂停 && this.hp > 0 && owner != null && owner.active
        && this.man === body && body.wingsToken === owner.token && this.状态 == owner.state;
};

wingsFinishAttack = function(body:MovieClip):Void {
    var owner:Object = this.wingsAttackOwner;
    if (owner == null || body.wingsToken !== owner.token) return;
    this.wingsCancelAttack();
    this.wingsReadyAt = this.wingsClock + this.wingsTuning.recoveryFrames;
    this.动画完毕();
};

// 只遍历本动作拥有的枪刃和静态翻转姿势，枪口取真实嵌套矩阵。
wingsFindMuzzle = function(body:MovieClip, marker:MovieClip):Object {
    if (marker == null) return null;
    var reference:Object = {x:0, y:0};
    marker.localToGlobal(reference);
    var scopes:Array = [body];
    var best:Object = null;
    var bestDistance:Number = Number.POSITIVE_INFINITY;
    for (var index:Number = 0; index < scopes.length; index++) {
        var scope:MovieClip = scopes[index];
        for (var key:String in scope) {
            var child = scope[key];
            if (typeof child != "movieclip" || child._parent !== scope) continue;
            if (child._name.indexOf("wingsPose") == 0 && index == 0) scopes.push(child);
            if (child._name.indexOf("wingsGun") != 0) continue;
            // 刚置入的静态姿势尚未执行子层首帧；注册点来自同一枪刃元件的已加载实例。
            if (child.枪口 != null && child.枪口._parent === child
                && !isNaN(child.枪口._x) && !isNaN(child.枪口._y)) {
                this.wingsMuzzleRegistration = {x:child.枪口._x, y:child.枪口._y};
            }
            var registration:Object = this.wingsMuzzleRegistration;
            if (registration == null) continue;
            var position:Object = {x:registration.x, y:registration.y};
            child.localToGlobal(position);
            var dx:Number = position.x - reference.x;
            var dy:Number = position.y - reference.y;
            var distance:Number = dx * dx + dy * dy;
            if (distance < bestDistance) { bestDistance = distance; best = {x:position.x, y:position.y, globalY:position.y}; }
        }
    }
    if (best != null) _root.gameworld.globalToLocal(best);
    return best;
};

wingsShoot = function(body:MovieClip, marker:MovieClip, angle:Number):Void {
    if (!this.wingsCanAct(body)) return;
    var muzzle:Object = this.wingsFindMuzzle(body, marker);
    if (muzzle == null) { this.wingsInvalidMuzzleCount++; this.wingsInvalidMuzzleFrame=body._currentframe; return; }
    var bullet:Object = _root.子弹属性初始化(marker, "穿刺子弹", this);
    bullet.shootX = muzzle.x;
    bullet.shootY = muzzle.y;
    bullet.转换中间y = muzzle.globalY;
    bullet.声音 = "shoot.wav";
    bullet.霰弹值 = 1;
    bullet.子弹散射度 = 8;
    bullet.子弹威力 = this.空手攻击力;
    bullet.子弹速度 = 25;
    bullet.Z轴攻击范围 = 30;
    bullet.击倒率 = 10;
    bullet.角度偏移 = isNaN(angle) ? 0 : angle;
    bullet.区域定位area = undefined;
    this.wingsHitCount++;
    _root.子弹区域shoot传递(bullet);
};

wingsSlash = function(body:MovieClip, area:MovieClip):Void {
    if (!this.wingsCanAct(body) || area == null) return;
    var bullet:Object = _root.子弹属性初始化(area, "近战子弹", this);
    bullet.声音 = "";
    bullet.霰弹值 = 1;
    bullet.子弹散射度 = 0;
    bullet.子弹威力 = this.空手攻击力;
    bullet.子弹速度 = 0;
    bullet.Z轴攻击范围 = 30;
    bullet.击倒率 = 2;
    bullet.不硬直 = true;
    bullet.区域定位area = area;
    this.wingsHitCount++;
    _root.子弹区域shoot传递(bullet);
};

wingsMove = function(body:MovieClip, amount:Number, trackZ:Number):Void {
    if (!this.wingsCanAct(body)) return;
    if (amount != 0 && !isNaN(amount)) {
        var right:Boolean = (this.方向 == "右") == (amount > 0);
        this.移动(right ? "右" : "左", Math.abs(amount));
    }
    if (!(trackZ > 0)) return;
    var target:MovieClip = _root.gameworld[this.攻击目标];
    if (!(target.hp > 0)) return;
    var dz:Number = target.Z轴坐标 - this.Z轴坐标;
    if (Math.abs(dz) > 2) this.移动(dz < 0 ? "上" : "下", Math.min(trackZ, Math.abs(dz)));
};

wingsFinishFlip = function(body:MovieClip):Void {
    if (!this.wingsCanAct(body)) return;
    var target:MovieClip = _root.gameworld[this.攻击目标];
    var dx:Number = Math.abs(target._x - this._x);
    var dz:Number = Math.abs(target.Z轴坐标 - this.Z轴坐标);
    if (!(target.hp > 0) || target.area == null || isNaN(dx) || isNaN(dz)
        || dz > this.wingsTuning.laneRange || dx > this.wingsTuning.shootRange) {
        this.wingsFinishAttack(body);
        return;
    }
    this.近战招式 = dx < 150 ? "斩击" : "射击";
    this.wingsBeginAttack(body, dx < 150 ? "slash" : "shoot");
    body.gotoAndPlay(this.近战招式);
};

wingsChooseAttack = function(dx:Number, dz:Number, height:Number):String {
    var tune:Object = this.wingsTuning;
    if (isNaN(dx) || isNaN(dz) || isNaN(height) || dx < 0 || dz < 0
        || dz > tune.laneRange || height > tune.maximumTargetHeight || this.wingsClock < this.wingsReadyAt) return "none";
    if (dx <= tune.comboRange && this.wingsClock >= this.wingsNextCombo) return "combo";
    if (dx <= tune.flipRange && this.wingsClock >= this.wingsNextFlip) return "flip";
    if (dx <= tune.slashRange) return "slash";
    if (dx <= tune.shootRange) return "shoot";
    return "none";
};

wingsTick = function():Void {
    if (_root.暂停) return;
    this.wingsClock++;
    if (!isNaN(this.hp) && this.hp <= 0) {
        this.wingsCancelAttack();
        if (this.状态 != "血腥死" && this.状态 != "消失") this.状态改变("血腥死");
        return;
    }
    var owner:Object = this.wingsAttackOwner;
    if (owner != null && (this.状态 != owner.state || this.man.wingsToken !== owner.token)) this.wingsCancelAttack();
    if (this.WingsAI模式 != "enhanced" || !(this.hp > 0) || this.倒地 || this.浮空 || this.硬直中) return;
    if (_root.控制目标 == this._name && _root.控制目标全自动 == false) return;
    if (this.状态 != "空手站立" && this.状态 != "空手行走" && this.状态 != "空手跑") return;
    if ((this.wingsClock & 3) != 0) return;
    var target:MovieClip = _root.gameworld[this.攻击目标];
    if (!(target.hp > 0) || target == this || target.area == null) return;
    var dx:Number = target._x - this._x;
    var dz:Number = target.Z轴坐标 - this.Z轴坐标;
    var height:Number = target.Z轴坐标 - target._y;
    if (isNaN(dx) || isNaN(dz) || isNaN(height)) return;
    this.x轴攻击范围 = 0;
    this.y轴攻击范围 = this.wingsTuning.laneRange;
    this.x轴保持距离 = this.wingsTuning.keepDistance;
    if (this.unitAI.data != null) {
        this.unitAI.data.xrange = 0;
        this.unitAI.data.zrange = this.y轴攻击范围;
        this.unitAI.data.xdistance = this.x轴保持距离;
    }
    if (this.wingsTargetName != target._name) {
        this.wingsTargetName = target._name;
        this.wingsReadyAt = this.wingsClock + this.wingsTuning.reactionFrames;
    }
    var action:String = this.wingsChooseAttack(Math.abs(dx), Math.abs(dz), height);
    if (action == "none") {
        this.左行 = dx < -this.wingsTuning.keepDistance;
        this.右行 = dx > this.wingsTuning.keepDistance;
        this.上行 = dz < -6;
        this.下行 = dz > 6;
        if (Math.abs(dx) > 280 && this.状态 != "空手跑") this.状态改变("空手跑");
        return;
    }
    this.左行 = this.右行 = this.上行 = this.下行 = false;
    this.方向改变(dx < 0 ? "左" : "右");
    this.近战招式 = action == "flip" ? "后空翻" : action == "slash" ? "斩击" : "射击";
    this.状态改变(action == "combo" ? "空手攻击" : "近战");
};

if (WingsAI模式 == "enhanced") {
    x轴攻击范围 = 0;
    y轴攻击范围 = wingsTuning.laneRange;
    x轴保持距离 = wingsTuning.keepDistance;
    if (unitAI.data != null) {
        unitAI.data.xrange = 0;
        unitAI.data.zrange = y轴攻击范围;
        unitAI.data.xdistance = x轴保持距离;
    }
}
