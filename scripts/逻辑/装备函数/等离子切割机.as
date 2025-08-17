// =======================================================
// 等离子切割机 · 装备生命周期函数
// =======================================================
import org.flashNight.arki.unit.Action.Regeneration.*;
import org.flashNight.arki.unit.*;

_root.装备生命周期函数.等离子切割机初始化 = function(ref, param)
{
    var target:MovieClip = ref.自机;

    /* ---------- 1. 帧常量 ---------- */
    ref.EXPAND_START = param.expandStart || 1;
    ref.EXPAND_END = param.expandEnd || 15;
    ref.SHOOT_START = param.shootStart || 16;
    ref.SHOOT_END = param.shootEnd || 23;
    ref.TRIGGER_FRAME = param.triggerFrame || 20;

    /* ---------- 2. 状态变量 ---------- */
    ref.isExpanding = false; // 展开动画中
    ref.isShooting = false; // 射击动画中
    ref.fireRequest = false; // 当帧射击触发
    ref.isDeployed = false; // 是否已展开到战斗状态
    ref.currentFrame = ref.EXPAND_START;
    ref.isWeaponActive = false;

    ref.basicReward = (param.basicReward != undefined) ? param.basicReward : 5; // 基础奖励
    ref.eliteReward = (param.eliteReward != undefined) ? param.eliteReward : 15; // 精英奖励
    ref.bossReward = (param.bossReward != undefined) ? param.bossReward : 25; // 首领奖励
    ref.rewarMax = (param.rewarMax != undefined) ? param.rewarMax : 25; // 最大奖励

    /* ---------- 3. 射击事件监听 ---------- */
    target.dispatcher.subscribe("长枪射击", function()
    {
        var prop:Object = target.man.子弹属性;
        var area:MovieClip = ref.自机.长枪_引用.枪口位置;
        // 等离子切割机的子弹属性

        prop.子弹种类 = "近战子弹";
        prop.区域定位area = area;

        ref.fireRequest = true;

        var frame:Number = ref.currentFrame;
        if (frame < ref.SHOOT_START || frame > SHOOT_END)
        {
            ref.currentFrame = ref.SHOOT_START;
        }
        else if (frame > ref.TRIGGER_FRAME)
        {
            ref.currentFrame = ref.TRIGGER_FRAME;
        }
    });

    target.dispatcher.subscribe("enemyKilled", function(hitTarget:MovieClip, bullet:MovieClip)
    {
        var targetUnit:MovieClip = ref.自机;
        if (bullet.子弹种类 === "近战子弹" && targetUnit.攻击模式 === "长枪")
        {
            var eliteLevel:Number = UnitUtil.getEliteLevel(hitTarget);
            var level:Number = Math.max(0, eliteLevel);
            var rewardBulletCount:Number;

            switch (level)
            {
                case 1: // 精英
                    rewardBulletCount = ref.eliteReward;
                    break;
                case 2: // 首领
                    rewardBulletCount = ref.bossReward;
                    break;
                default:
                    rewardBulletCount = ref.basicReward; // 超过最大奖励
            }

            // 使用RegenerationCore的单体百分比恢复功能
            RegenerationCore.executeRegeneration(
                targetUnit,
                RegenerationCore.HEALTH_REGEN,
                RegenerationCore.PERCENTAGE,
                "single",
                rewardBulletCount / 100,
                {
                    multiplier: 1,
                    effectName: "药剂动画-2",
                    effectScale: 100,
                    effectStick: true
                }
            );
        }
    });
};

/*--------------------------------------------------------
 * 周期函数
 *------------------------------------------------------*/
_root.装备生命周期函数.等离子切割机周期 = function(ref)
{
    _root.装备生命周期函数.移除异常周期函数(ref);

    var 自机 = ref.自机;
    var 长枪 = 自机.长枪_引用;

    /* ===== 0. 武器激活检测 ===== */
    ref.isWeaponActive = (自机.攻击模式 === "长枪");

    if (!ref.isWeaponActive)
    {
        // 收枪：立即复位并清状态
        ref.isExpanding = ref.isShooting = ref.fireRequest = ref.isDeployed = false;
        ref.currentFrame = ref.EXPAND_START;
        长枪.gotoAndStop(ref.currentFrame);
        return;
    }

    /* ===== 1. 读取并清除 fireRequest ===== */
    var wantFire = ref.fireRequest;
    ref.fireRequest = false;

    /* ===== 2. 武器展开检测 ===== */
    if (!ref.isDeployed && !ref.isExpanding)
    {
        // 武器激活时自动开始展开
        ref.isExpanding = true;
        ref.currentFrame = ref.EXPAND_START;
        长枪.gotoAndStop(ref.currentFrame);
        return;
    }

    /* ===== 3. 射击触发 ===== */
    if (wantFire && ref.isDeployed && !ref.isShooting)
    {
        // 开始射击动画
        ref.isShooting = true;

        长枪.gotoAndStop(ref.currentFrame);
        return;
    }

    /* ===== 4. 动画推进 ===== */
    // 4-A 展开动画段 (1-15帧)
    if (ref.isExpanding)
    {
        长枪.gotoAndStop(ref.currentFrame);

        if (ref.currentFrame < ref.EXPAND_END)
        {
            ++ref.currentFrame;
        }
        else
        {
            // 展开完成，进入战斗待机状态
            ref.isExpanding = false;
            ref.isDeployed = true;
            ref.currentFrame = ref.EXPAND_END; // 停在第15帧
        }
        return;
    }

    // 4-B 射击动画段 (16-23帧或20-23帧)
    if (ref.isShooting)
    {
        长枪.gotoAndStop(ref.currentFrame);

        if (ref.currentFrame < ref.SHOOT_END)
        {
            ++ref.currentFrame;
        }
        else
        {
            // 射击动画完成，回到战斗待机状态(15帧)
            ref.isShooting = false;
            ref.currentFrame = ref.EXPAND_END;
        }
        return;
    }

    // 战斗待机状态：保持在第15帧
    if (ref.isDeployed && ref.currentFrame !== ref.EXPAND_END)
    {
        ref.currentFrame = ref.EXPAND_END;
    }

    /* ===== 5. 绘制 ===== */
    长枪.gotoAndStop(ref.currentFrame);
};