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
        damage: number;      // 当前显示伤害（合并模式下为累计总伤）
        packed: number;
        efText: string;
        efEmoji: string;
        lifeSteal: number;
        shieldAbsorb: number;
        frame: number;       // 0-13 可见动画帧，14 = 已过期
        hitCount: number;    // 命中段数（≥1，合并模式下累加）
    }
}
