// =======================================================
// 等离子切割机 · 装备生命周期函数（含击杀动画 26–35 帧）
// =======================================================
import org.flashNight.arki.unit.Action.Regeneration.*;
import org.flashNight.arki.unit.*;
import org.flashNight.gesh.object.*;

_root.装备生命周期函数.等离子切割机初始化 = function(ref, param) {
    var target:MovieClip = ref.自机;

    /* ---------- 1. 帧常量 ---------- */
    ref.EXPAND_START  = (param.expandStart  != undefined) ? param.expandStart  : 1;
    ref.EXPAND_END    = (param.expandEnd    != undefined) ? param.expandEnd    : 15;
    ref.SHOOT_START   = (param.shootStart   != undefined) ? param.shootStart   : 16;
    ref.SHOOT_END     = (param.shootEnd     != undefined) ? param.shootEnd     : 23;
    ref.TRIGGER_FRAME = (param.triggerFrame != undefined) ? param.triggerFrame : 20;
    ref.KILL_START    = (param.killStart    != undefined) ? param.killStart    : 26;
    ref.KILL_END      = (param.killEnd      != undefined) ? param.killEnd      : 35;

    /* ---------- 2. 状态变量 ---------- */
    ref.isExpanding     = false; // 展开动画中
    ref.isShooting      = false; // 射击动画中
    ref.isKilling       = false; // 【新增】击杀动画中
    ref.killAnimQueue   = 0;     // 【新增】击杀动画排队次数
    ref.fireRequest     = false; // 当帧射击触发
    ref.isDeployed      = false; // 是否已展开到战斗状态
    ref.currentFrame    = ref.EXPAND_START;
    ref.isWeaponActive  = false;

    ref.basicReward = (param.basicReward != undefined) ? param.basicReward : 5;   // 基础奖励
    ref.eliteReward = (param.eliteReward != undefined) ? param.eliteReward : 15;  // 精英奖励
    ref.bossReward  = (param.bossReward  != undefined) ? param.bossReward  : 25;  // 首领奖励
    // FIX: 兼容旧参数名 rewarMax，统一为 rewardMax，当前未直接使用但保留字段以便后续逻辑
    ref.rewardMax  = (param.rewardMax != undefined) ? param.rewardMax :
                     (param.rewarMax != undefined) ? param.rewarMax : 25;

    /* ---------- 3. 射击事件监听 ---------- */
    target.dispatcher.subscribe("长枪射击", function() {
        var prop:Object  = target.man.子弹属性;
        var area:MovieClip = ref.自机.长枪_引用.枪口位置;

        // 等离子切割机的子弹属性
        prop.子弹种类 = "近战子弹";
        prop.区域定位area = area;

        ref.fireRequest = true;

        var frame:Number = ref.currentFrame;
        // FIX: 漏写 ref. 前缀
        if (frame < ref.SHOOT_START || frame > ref.SHOOT_END) {
            ref.currentFrame = ref.SHOOT_START;
        } else if (frame > ref.TRIGGER_FRAME) {
            ref.currentFrame = ref.TRIGGER_FRAME;
        }
    });

    /* ---------- 4. 击杀事件：触发击杀动画 + 奖励 + 大穿刺子弹 ---------- */
    target.dispatcher.subscribe("enemyKilled", function(hitTarget:MovieClip, bullet:MovieClip) {
        var targetUnit:MovieClip = ref.自机;
        // 仅在本武器近战子弹且处于长枪攻击模式时生效
        if (bullet.子弹种类 === "近战子弹" && targetUnit.攻击模式 === "长枪") {
            // —— 奖励回血（按百分比）
            var eliteLevel:Number = UnitUtil.getEliteLevel(hitTarget);
            var level:Number = Math.max(0, eliteLevel);
            var rewardBulletCount:Number;
            switch (level) {
                case 1: rewardBulletCount = ref.eliteReward; break; // 精英
                case 2: rewardBulletCount = ref.bossReward;  break; // 首领
                default: rewardBulletCount = ref.basicReward;       // 普通
            }
            RegenerationCore.executeRegeneration(
                targetUnit,
                RegenerationCore.HEALTH_REGEN,
                RegenerationCore.PERCENTAGE,
                "single",
                rewardBulletCount / 100, // 百分比
                {
                    multiplier: 1,
                    effectName: "药剂动画-2",
                    effectScale: 100,
                    effectStick: true
                }
            );

            // —— 追加发射“等离子大穿刺子弹”
            var prop:Object = ObjectUtil.clone(targetUnit.man.子弹属性);
            var muzzle:MovieClip = targetUnit.长枪_引用.枪口位置;
            var myPoint:Object = {x: muzzle._x, y: muzzle._y + 20};
            targetUnit.长枪_引用.localToGlobal(myPoint);
            _root.gameworld.globalToLocal(myPoint);
            // FIX: 自机 -> targetUnit
            prop.声音 = targetUnit.副武器子弹声音;
            prop.子弹种类 = "等离子大穿刺子弹";
            prop.子弹威力 = prop.子弹威力 * 5;
            prop.子弹速度 = 50;
            prop.击中地图效果 = "";
            prop.击中后子弹的效果 = "";
            prop.shootX = myPoint.x;
            prop.shootY = myPoint.y;
            // FIX: 自机 -> targetUnit
            prop.shootZ = targetUnit.Z轴坐标;
            _root.子弹区域shoot传递(prop);

            // —— 触发击杀动画（优先级最高）
            if (ref.isKilling) {
                // 播放中叠加一次排队
                ref.killAnimQueue++;
            } else {
                ref.isKilling   = true;
                ref.isShooting  = false; // 播击杀动画时屏蔽射击段
                ref.isExpanding = false; // 强行打断展开段
                ref.currentFrame = ref.KILL_START;
            }
        }
    });
};

/*--------------------------------------------------------
 * 周期函数
 *------------------------------------------------------*/
_root.装备生命周期函数.等离子切割机周期 = function(ref) {
    _root.装备生命周期函数.移除异常周期函数(ref);

    var 自机:MovieClip = ref.自机;
    var 长枪:MovieClip = 自机.长枪_引用;

    /* ===== 0. 武器激活检测 ===== */
    ref.isWeaponActive = (自机.攻击模式 === "长枪");

    if (!ref.isWeaponActive) {
        // 收枪：立即复位并清状态
        ref.isExpanding   = false;
        ref.isShooting    = false;
        ref.isKilling     = false;   // 【新增】清击杀状态
        ref.killAnimQueue = 0;       // 【新增】清队列
        ref.fireRequest   = false;
        ref.isDeployed    = false;
        ref.currentFrame  = ref.EXPAND_START;
        长枪.gotoAndStop(ref.currentFrame);
        return;
    }

    /* ===== 1. 读取并清除 fireRequest ===== */
    var wantFire:Boolean = ref.fireRequest;
    ref.fireRequest = false;

    /* ===== 2. 击杀动画推进（优先级最高） ===== */
    if (ref.isKilling) {
        长枪.gotoAndStop(ref.currentFrame);

        if (ref.currentFrame < ref.KILL_END) {
            ++ref.currentFrame;
        } else {
            // 一个击杀段落播放完成
            if (ref.killAnimQueue > 0) {
                // 还有排队的击杀动画，继续下一轮
                ref.killAnimQueue--;
                ref.currentFrame = ref.KILL_START;
            } else {
                // 播放完毕，回到战斗待机（15帧）
                ref.isKilling    = false;
                ref.isShooting   = false;
                ref.isExpanding  = false;
                ref.isDeployed   = true;          // 仍处于战斗展开态
                ref.currentFrame = ref.EXPAND_END; // 15
            }
        }
        return;
    }

    /* ===== 3. 武器展开检测 ===== */
    if (!ref.isDeployed && !ref.isExpanding) {
        // 武器激活时自动开始展开
        ref.isExpanding  = true;
        ref.currentFrame = ref.EXPAND_START;
        长枪.gotoAndStop(ref.currentFrame);
        return;
    }

    /* ===== 4. 射击触发（击杀动画期间已被屏蔽） ===== */
    if (wantFire && ref.isDeployed && !ref.isShooting /* && !ref.isKilling */) {
        ref.isShooting = true;
        // currentFrame 在“长枪射击”事件里已被定位到 START/触发帧
        长枪.gotoAndStop(ref.currentFrame);
        return;
    }

    /* ===== 5. 动画推进 ===== */
    // 5-A 展开动画段 (1-15帧)
    if (ref.isExpanding) {
        长枪.gotoAndStop(ref.currentFrame);

        if (ref.currentFrame < ref.EXPAND_END) {
            ++ref.currentFrame;
        } else {
            // 展开完成，进入战斗待机状态
            ref.isExpanding  = false;
            ref.isDeployed   = true;
            ref.currentFrame = ref.EXPAND_END; // 15
        }
        return;
    }

    // 5-B 射击动画段 (16-23帧或20-23帧)
    if (ref.isShooting) {
        长枪.gotoAndStop(ref.currentFrame);

        if (ref.currentFrame < ref.SHOOT_END) {
            ++ref.currentFrame;
        } else {
            // 射击动画完成，回到战斗待机状态(15帧)
            ref.isShooting   = false;
            ref.currentFrame = ref.EXPAND_END;
        }
        return;
    }

    // 战斗待机状态：保持在第15帧
    if (ref.isDeployed && ref.currentFrame !== ref.EXPAND_END) {
        ref.currentFrame = ref.EXPAND_END;
    }

    /* ===== 6. 绘制 ===== */
    长枪.gotoAndStop(ref.currentFrame);
};
