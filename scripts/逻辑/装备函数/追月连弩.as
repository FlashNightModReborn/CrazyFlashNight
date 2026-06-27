// =====================================================================
// 追月连弩 - 连弩射击动画生命周期（纯视觉，不参与战斗 / 弹药结算）
// ---------------------------------------------------------------------
// 影片剪辑结构（dressup「枪-长枪-追月连弩」，素材在 flashswf/arts/new/黑洞军工.fla）：
//   长枪_引用
//     └─ 动画 (recoil)        每次射击 1→6→1 乒乓后坐
//          └─ 箭筒 (quiver)   按剩余弹容播放某一 5 帧档位后停在档首
//
// 动画帧语义：帧1 = 归位(已上膛待发)；帧2 = 上膛/空载姿态。
//   · 打空(剩余=0)：回放停在帧2 而非帧1，用上膛姿态遮掩"没箭却像已上膛"的破绽。
//   · 装填回充(剩余 0→≥1，tube 逐发亦可)：从帧2 续放 2→1 归位。
//
// 弹容 → 箭筒档位（剩余发数 = 长枪弹匣容量 - 长枪.value.shot，取射击后的值）：
//   >5 → 1-5(满)   5 → 6-10   4 → 11-15   3 → 16-20
//    2 → 21-25     1 → 26-30  0 → 31-35
//
// 触发方式：每帧比对剩余弹容增量（射击 = 减、换弹 = 增），不依赖 "长枪射击"
//          事件时序（该事件在 value.shot 递增之前 publish，直接读会差一发）。
//
// FLA 依赖前提（追月连弩 元件需满足，否则相应分支自动空转不报错）：
//   1) 动画 子 MC ≥ 6 帧，无自带 stop/play 帧脚本（由本函数 gotoAndStop 驱动）；
//      帧1=归位、帧2=上膛/空载（空弹与装填期 hold 于此）
//   2) 箭筒 子 MC ≥ 35 帧，且作为同一实例贯穿 动画 的全部 1-6 帧（后坐期间不消失）
//
// 帧数 / 速度 / 档位 / 空弹停帧 均可由 XML <init><initParam> 覆盖（见 初始化 顶部）。
// 参照既有长枪动画范式：M134.as / M249.as。
// =====================================================================

// 剩余发数 → 箭筒档位首帧
_root.装备生命周期函数.追月连弩档位 = function(ref:Object, remaining:Number):Number {
    if (isNaN(remaining) || remaining > ref.箭筒低弹阈值) {
        return ref.箭筒满档起始;
    }
    if (remaining < 0) remaining = 0;
    // 低弹区紧接满档之后：阈值..0 共 (阈值 + 1) 档，每档 箭筒档位帧数 帧
    return ref.箭筒满档起始 + ref.箭筒档位帧数
         + (ref.箭筒低弹阈值 - remaining) * ref.箭筒档位帧数;
};

_root.装备生命周期函数.追月连弩初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;

    // ---- 可调参数（缺省值见右侧）----
    ref.动画总帧     = param.bowFrames          || 6;  // 动画 后坐循环顶帧
    ref.动画速度     = param.animSpeed          || 1;  // 每游戏帧推进的时间轴帧数
    ref.空弹停帧     = param.emptyHoldFrame     || 2;  // 空弹/装填期 动画 hold 帧（遮掩上膛）
    ref.箭筒档位帧数 = param.quiverBandSize     || 5;  // 每个弹容档位帧数
    ref.箭筒满档起始 = param.quiverFullStart    || 1;  // 弹容 > 阈值 时的档位首帧
    ref.箭筒低弹阈值 = param.quiverLowThreshold || 5;  // 进入逐档显示的剩余发数阈值

    // ---- 运行状态 ----
    ref.capacity = target["长枪弹匣容量"];                  // 弹匣容量（发）
    var remaining:Number = ref.capacity - target.长枪.value.shot;
    ref.上次剩余 = remaining;                               // 增量检测基准

    ref.动画播放中 = false;
    // 空仓装备时直接停在 空弹停帧，避免一上手就露怯（首帧 周期 即 gotoAndStop 落实）
    ref.动画帧     = (remaining == 0) ? ref.空弹停帧 : 1;
    ref.动画方向   = 1;                                     // 1 = 正放(1→6)  -1 = 回放(6→1)

    ref.箭筒起始   = _root.装备生命周期函数.追月连弩档位(ref, remaining);
    ref.箭筒帧     = ref.箭筒起始;
    ref.箭筒播放中 = false;
};

_root.装备生命周期函数.追月连弩周期 = function(ref:Object, param:Object) {
    if (!EquipmentTick.open(ref)) return;   // 异常清理 + 同帧去重
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    if (gun == undefined) return;
    var anim:MovieClip = gun.动画;
    if (anim == undefined) return;

    // 自愈：若 初始化 早于弹匣容量就绪，capacity 为 NaN，这里补读
    if (isNaN(ref.capacity)) {
        ref.capacity = target["长枪弹匣容量"];
        ref.上次剩余 = ref.capacity - target.长枪.value.shot;
    }

    // ---- 1. 增量检测：射击(剩余减) / 换弹(剩余增) ----
    var remaining:Number = ref.capacity - target.长枪.value.shot;
    if (remaining < ref.上次剩余) {
        // 射击：启动 动画 后坐 + 箭筒 当前档位播放
        ref.动画播放中 = true;
        ref.动画帧 = 1 - ref.动画速度;          // 本帧首次推进后正好落到第 1 帧
        ref.动画方向 = 1;

        ref.箭筒起始 = _root.装备生命周期函数.追月连弩档位(ref, remaining);
        ref.箭筒帧 = ref.箭筒起始 - ref.动画速度; // 同理首次推进后落到档首
        ref.箭筒播放中 = true;
    } else if (remaining > ref.上次剩余) {
        // 换弹 / 补弹：箭筒 直接回到对应档首；动画 若停在 空弹停帧 则续放回归位帧
        ref.箭筒起始 = _root.装备生命周期函数.追月连弩档位(ref, remaining);
        ref.箭筒帧 = ref.箭筒起始;
        ref.箭筒播放中 = false;
        if (!ref.动画播放中 && ref.动画帧 > 1) {   // 仅在已 hold 时续放，避免打断进行中的后坐
            ref.动画播放中 = true;
            ref.动画方向 = -1;                     // 续放方向：回归位
        }
    }
    ref.上次剩余 = remaining;

    // ---- 2. 动画 后坐 1→6→1 乒乓；空弹时回放停在 空弹停帧 遮掩上膛 ----
    //    停帧随当前弹容动态取值：空弹=空弹停帧(2)，有弹=归位帧(1)。
    //    故装填后(remaining>0) 进行中的回放会自然越过 2 续到 1。
    var 动画停帧:Number = (remaining == 0) ? ref.空弹停帧 : 1;
    if (ref.动画播放中) {
        ref.动画帧 += ref.动画速度 * ref.动画方向;
        if (ref.动画方向 > 0 && ref.动画帧 >= ref.动画总帧) {
            ref.动画帧 = ref.动画总帧;
            ref.动画方向 = -1;
        } else if (ref.动画方向 < 0 && ref.动画帧 < 动画停帧) {
            ref.动画帧 = 动画停帧;
            ref.动画播放中 = false;
        }
    }
    anim.gotoAndStop(Math.round(ref.动画帧));   // 常驻显示（空仓装备 / 空弹 hold 同样生效）

    // ---- 3. 箭筒 档位 5 帧播放一次后停在档首（常驻显示当前弹容档位）----
    var quiver:MovieClip = anim.箭筒;
    if (quiver != undefined) {
        if (ref.箭筒播放中) {
            ref.箭筒帧 += ref.动画速度;
            if (ref.箭筒帧 > ref.箭筒起始 + ref.箭筒档位帧数 - 1) {
                ref.箭筒帧 = ref.箭筒起始;   // 回到档首
                ref.箭筒播放中 = false;
            }
        }
        quiver.gotoAndStop(Math.round(ref.箭筒帧));
    }
};
