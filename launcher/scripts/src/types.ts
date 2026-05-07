/// <reference path="camera.ts" />
/// <reference path="animation.ts" />
/// <reference path="parser.ts" />
/// <reference path="pool.ts" />

namespace HitNumber {
    export interface CameraSnapshot {
        gx: number;   // gameworld._x
        gy: number;   // gameworld._y
        sx: number;   // gameworld._xscale * 0.01 (scale factor)
    }

    export interface ActiveEntry {
        worldX: number;      // 含随机偏移的显示坐标
        worldY: number;
        rawX: number;        // 原始目标坐标（用于同目标合并判定）
        rawY: number;
        targetDmg: number;   // 目标总伤（合并时立即更新）
        displayDmg: number;  // 当前显示伤害（逐帧递增动画）
        packed: number;
        efText: string;
        efEmoji: string;
        lifeSteal: number;
        shieldAbsorb: number;
        frame: number;       // 0-13 可见动画帧，14 = 已过期
        targetHits: number;  // 目标段数（合并时立即更新）
        displayHits: number; // 当前显示段数（逐帧递增动画）
        unitId: string;      // 合并键：来自 AS2 hitTarget._name；空串 = 无 ID（旧协议）
        isAggregator: boolean;  // true = unit 头顶累计总伤数字（长寿、跟随、Z-top）
                                // false = 普通飘字（短期反馈，14 帧浮起飞走）
        silentFrames: number;   // 仅 aggregator 用：自上次新命中后经过的帧数。
                                // 静默 ≥ AGGREGATOR_QUIET_FRAMES 后才开始走衰退动画
        pulseTimer: number;     // 视觉脉动倒计时（命中瞬间设为 PULSE_DURATION，每帧 -- 衰减回 0）
                                // tick 渲染时按 pulseTimer/PULSE_DURATION 应用额外字号加成
        maxSegmentDmg: number;  // aggregator 跟踪的"最大单段伤害"。新进段大于此值时
                                // packed 的 size/colorId 跟随刷新（暴击段视觉接管）
        efFlagDmgSum: number[]; // 长度 9：每个 efFlag 累计的伤害量（不是段数）。
                                // 用于算 target_scale = ratio 映射，驱动 displayFlagScales 衰减
        displayFlagScales: number[]; // 长度 9：每个 efFlag 当前渲染字号（0..1）。
                                // 命中触发该 flag 时强制 = 1.0（即时反馈），
                                // 每帧向 target_scale 线性追赶（DECAY_STEP），最终消失或稳定
        colorIdDmgSum: number[];  // 长度 11：每个 colorId 累计的伤害量。tick 时算 dominant
        displayR: number;         // 当前渲染颜色 R 通道（0..255 浮点，输出时 round）
        displayG: number;         // 当前渲染颜色 G 通道
        displayB: number;         // 当前渲染颜色 B 通道
                                  // 每次命中瞬时刷新到该段色（短期反馈），后续帧指数衰减回 dominant
        efTextColorId: number;    // EF_DMG_TYPE_LABEL 标签字符串（"热"/"真"等）的来源 colorId
                                  // 与 efText 同步更新（每次 EF_DMG_TYPE_LABEL 段命中时记录该段 colorId）
                                  // 渲染端用此 colorId 查 COLOR_TABLE 决定标签颜色，与主数字色解耦
    }
}
