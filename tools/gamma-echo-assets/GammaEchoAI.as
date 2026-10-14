// γ-ECHO 私有决策：不改共享 AI、攻击帧、子弹威力或段数。
// baseline 保留诺亚原始索敌脚本，供同面板斗兽对照。
// 65 级起原普通攻击获得刚体；高等级镜像未证明私有策略有收益。
// 显式模式只供隔离对照，正常生成按等级选择已验证的默认分支。
if (克隆兽AI模式 != "baseline" && 克隆兽AI模式 != "enhanced") {
    克隆兽AI模式 = 等级 >= 65 ? "baseline" : "enhanced";
}
// 暴君型摄食续航沿用子弹继承与 LifeStealDamageHandle 的统一结算。
// 普通生成不接受诊断开关；λ 型始终不获得此项固有吸血。
吸血 = 克隆兽完全体 ? 5 : 0;
if (_arenaCalibrationUnit === true && 克隆兽吸血模式 == "off") 吸血 = 0;
gammaEchoDecisionCount = 0;
gammaEchoSkillCount = 0;
gammaEchoAlignCount = 0;

gammaEchoChooseSkill = function(distanceX:Number, distanceZ:Number, targetHeight:Number):String {
    if (isNaN(distanceX) || isNaN(distanceZ) || isNaN(targetHeight)) return "none";
    if (distanceX < 0 || distanceZ < 0 || distanceZ > 24 || targetHeight > 65) return "none";
    if (distanceX <= 150) return "撕裂嘶吼";
    if (distanceX <= 230) return "跳跃撕咬";
    if (distanceX <= 430) return "跑动捕杀";
    return "none";
};

gammaEchoThink = function(sensor:MovieClip):Void {
    var actor:MovieClip = this;
    if (_root.暂停 || !(actor.hp > 0) || actor.倒地 || actor.浮空 || actor.硬直中) return;
    if (_root.控制目标 == actor._name && _root.控制目标全自动 == false) return;
    if (actor.状态 != "空手站立" && actor.状态 != "空手行走" && actor.状态 != "空手跑") return;
    var target:MovieClip = _root.gameworld[actor.攻击目标];
    if (!(target.hp > 0) || target == actor || target.area == null) return;
    var dx:Number = target._x - actor._x;
    var dz:Number = target.Z轴坐标 - actor.Z轴坐标;
    var height:Number = target.Z轴坐标 - target._y;
    if (isNaN(dx) || isNaN(dz) || isNaN(height)) return;
    actor.gammaEchoDecisionCount++;
    // 与现有行走函数共享方向标志，每帧仍只有原生控制块执行一次碰撞移动。
    if (Math.abs(dz) > 24 || Math.abs(dx) > 430 || !sensor.hitTest(target.area)) {
        actor.上行 = dz < -6;
        actor.下行 = dz > 6;
        actor.左行 = dx < -70;
        actor.右行 = dx > 70;
        actor.gammaEchoAlignCount++;
        if (Math.abs(dx) > 230 && actor.状态 != "空手跑") actor.状态改变("空手跑");
        return;
    }
    var move:String = actor.gammaEchoChooseSkill(Math.abs(dx), Math.abs(dz), height);
    if (move == "none") return;
    actor.左行 = false;
    actor.右行 = false;
    actor.上行 = false;
    actor.下行 = false;
    if (dx < 0) actor.方向改变("左");
    else if (dx > 0) actor.方向改变("右");
    // 出招间隔由原动作完整时间轴约束，不在收招后叠加私有空等。
    actor.gammaEchoSkillCount++;
    actor.gammaEchoLastMove = move;
    actor.近战招式 = move;
    actor.状态改变("近战");
};

if (克隆兽AI模式 == "enhanced") {
    // 私有控制器独占自动出招，避免通用近身普攻抢占具有原生刚体的近战主招。
    x轴攻击范围 = 0;
    y轴攻击范围 = 24;
    x轴保持距离 = 100;
    if (unitAI.data != null) {
        unitAI.data.xrange = 0;
        unitAI.data.zrange = 24;
        unitAI.data.xdistance = 100;
    }
}
// 仅在隔离标定单位上保留私有配置；不占用 ArenaSkillCache 的严格结果字段。
if (_arenaCalibrationUnit === true) {
    gammaEchoArenaAudit = {
        kind:"GammaEchoAI",
        revision:5,
        mode:克隆兽AI模式,
        fullPower:克隆兽完全体,
        lifeStealPercent:吸血,
        attackRange:x轴攻击范围,
        laneRange:y轴攻击范围,
        keepDistance:x轴保持距离,
        hpMin:hp_min,
        hpMax:hp_max,
        baseAttack:空手攻击力,
        damageMultiplier:1
    };
}
