﻿// =======================================================
// GM6_LYNX · 纯动画逻辑（互斥状态机版）
// 1–15：展开；15–23：射击；非“长枪”则收起
// =======================================================

_root.装备生命周期函数.GM6_LYNX初始化 = function (ref, param)
{
    var actor:MovieClip = ref.自机;
    var rig:MovieClip   = actor.长枪_引用;

    // ---- 帧区间 ----
    ref.OPEN_START = (param.openStart != undefined) ? param.openStart : 1;
    ref.OPEN_END   = (param.openEnd   != undefined) ? param.openEnd   : 15;
    ref.FIRE_START = (param.fireStart != undefined) ? param.fireStart : 15;
    ref.FIRE_END   = (param.fireEnd   != undefined) ? param.fireEnd   : 23;

    // ---- 速度（每周期推进帧数）----
    ref.openSpeed  = Math.max(1, (param.openSpeed  != undefined) ? param.openSpeed  : 1);
    ref.closeSpeed = Math.max(1, (param.closeSpeed != undefined) ? param.closeSpeed : 1);
    ref.fireSpeed  = Math.max(1, (param.fireSpeed  != undefined) ? param.fireSpeed  : 1);

    // ---- 状态枚举 ----
    ref.STATE_COLLAPSE = 0;
    ref.STATE_EXPAND   = 1;
    ref.STATE_READY    = 2; // 展开完成待机
    ref.STATE_FIRE     = 3;

    // ---- 运行时 ----
    ref.state       = ref.STATE_COLLAPSE;
    ref.curFrame    = ref.OPEN_START;
    ref.pendingFire = false; // 展开完成后立刻射击

    // 初始根据姿态定状态
    var isRifle = (actor.攻击模式 == "长枪");
    if (isRifle) {
        // 需要展开到 15
        ref.state    = ref.STATE_EXPAND;
        ref.curFrame = ref.OPEN_START;
    } else {
        ref.state    = ref.STATE_COLLAPSE;
        ref.curFrame = ref.OPEN_START;
    }

    if (rig) rig.gotoAndStop(ref.curFrame);

    // 订阅“长枪射击”
    actor.dispatcher.subscribe("updateBullet", function () {
        // 仅在“长枪”姿态下响应
        if (actor.攻击模式 != "长枪") return;

        if (ref.state == ref.STATE_READY) {
            ref.state    = ref.STATE_FIRE;
            ref.curFrame = ref.FIRE_START;
        } else if (ref.state == ref.STATE_EXPAND) {
            // 展开尚未完成，则标记待射，展开到位后自动转 FIRE
            ref.pendingFire = true;
        } else if (ref.state == ref.STATE_FIRE) {
            // 正在射击中：忽略或可做队列，这里选择忽略以保持节奏稳定
        } else if (ref.state == ref.STATE_COLLAPSE) {
            // 正在收起但玩家开火：先转展开，再挂起待射
            ref.state       = ref.STATE_EXPAND;
            ref.pendingFire = true;
        }
    });
};


// =======================================================
// 周期：按状态推进（互斥执行）
// =======================================================
_root.装备生命周期函数.GM6_LYNX周期 = function (ref)
{
    var actor:MovieClip = ref.自机;
    var rig:MovieClip   = actor.长枪_引用;
    if (!rig) return;

    var isRifle = (actor.攻击模式 == "长枪");

    // 顶层姿态守护：非长枪 -> 强制收起（互斥切换，清空待射）
    if (!isRifle && ref.state != ref.STATE_COLLAPSE) {
        ref.state       = ref.STATE_COLLAPSE;
        ref.pendingFire = false;
    }
    // 长枪姿态且处于收起：转入展开
    if (isRifle && ref.state == ref.STATE_COLLAPSE) {
        // 若已在1帧则进入展开，否则继续收起到1再展开
        if (ref.curFrame <= ref.OPEN_START) {
            ref.state = ref.STATE_EXPAND;
        }
    }

    // ---- 互斥状态分支 ----
    switch (ref.state) {
        case ref.STATE_COLLAPSE:
            // 递减到 OPEN_START
            if (ref.curFrame > ref.OPEN_START) {
                ref.curFrame = Math.max(ref.OPEN_START, ref.curFrame - ref.closeSpeed);
            }
            // 保持在1帧
            break;

        case ref.STATE_EXPAND:
            if (ref.curFrame < ref.OPEN_END) {
                ref.curFrame = Math.min(ref.OPEN_END, ref.curFrame + ref.openSpeed);
            }
            if (ref.curFrame >= ref.OPEN_END) {
                // 展开完成：就绪或直接开火
                if (ref.pendingFire) {
                    ref.pendingFire = false;
                    ref.state       = ref.STATE_FIRE;
                    ref.curFrame    = ref.FIRE_START;
                } else {
                    ref.state       = ref.STATE_READY;
                    ref.curFrame    = ref.OPEN_END; // 定格 15
                }
            }
            break;

        case ref.STATE_READY:
            // 就绪定格在 15；若姿态变了，顶层守护会切回 COLLAPSE
            ref.curFrame = ref.OPEN_END;
            break;

        case ref.STATE_FIRE:
            if (ref.curFrame < ref.FIRE_END) {
                ref.curFrame = Math.min(ref.FIRE_END, ref.curFrame + ref.fireSpeed);
            }
            if (ref.curFrame >= ref.FIRE_END) {
                // 射击结束：回到 15 并进入就绪
                ref.curFrame = ref.FIRE_START;
                ref.state    = ref.STATE_READY;
            }
            break;
    }

    rig.gotoAndStop(ref.curFrame);
};
