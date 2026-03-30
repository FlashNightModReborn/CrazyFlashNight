/// <reference path="types.ts" />

namespace HitNumber {
    /**
     * 从 打击伤害数字.xml 提取的关键帧数据
     *
     * SWF Layer 2 关键帧（XML index → Matrix [a, d, tx, ty] + GlowFilter blur）：
     *   0 (dur 4, static):  a=1.3176 tx=-241.65 ty=-136   blur=4
     *   4 (dur 3, tween→7): a=1.0687 tx=-196    ty=-131.1 blur=3
     *   7 (dur 2, static):  a=1.0    tx=-183.4  ty=-129.75 blur=3
     *   9 (dur 1, tween→10):a=0.9291 tx=-170.4  ty=-135.85 blur=2
     *  10 (dur 3, tween→13):a=0.9056 tx=-166.1  ty=-137.9  blur=2
     *  13 (dur 1):          a=0.3280 tx=-88.7   ty=-136.5  blur=1
     *  14: recovery (empty)
     *
     * Flash motion tween = 线性插值（无 easing）
     * static 帧段（无 tweenType）= 保持关键帧值不变
     *
     * 文本字段尺寸: 229×39.45, transformationPoint = (114.5, 19.65)
     * 文本中心 = Matrix(a) * center + tx  → 即 offsetXLUT / offsetYLUT
     */

    /** 文本字段中心点（SWF transformationPoint） */
    const TEXT_CENTER_X = 114.5;
    const TEXT_CENTER_Y = 19.65;

    // ====== scale LUT (14 帧) ======
    export const scaleLUT: number[] = [
        1.3176, 1.3176, 1.3176, 1.3176,               // 0-3: static
        1.0687,                                         // 4
        1.0687 + (1.0 - 1.0687) * (1 / 3),             // 5
        1.0687 + (1.0 - 1.0687) * (2 / 3),             // 6
        1.0, 1.0,                                       // 7-8: static
        0.9291,                                         // 9
        0.9056,                                         // 10
        0.9056 + (0.3280 - 0.9056) * (1 / 3),          // 11
        0.9056 + (0.3280 - 0.9056) * (2 / 3),          // 12
        0.3280                                          // 13
    ];

    // ====== blur LUT (14 帧, GlowFilter 偏移半径) ======
    export const blurLUT: number[] = [
        4, 4, 4, 4,                                     // 0-3
        3, 3, 3, 3, 3,                                  // 4-8
        2,                                               // 9
        2,                                               // 10
        2 + (1 - 2) * (1 / 3),                          // 11
        2 + (1 - 2) * (2 / 3),                          // 12
        1                                                // 13
    ];

    // ====== tx LUT (Matrix tx, 14 帧) ======
    const txLUT: number[] = [
        -241.65, -241.65, -241.65, -241.65,             // 0-3: static
        -196,                                            // 4
        -196 + (-183.4 - (-196)) * (1 / 3),             // 5: -191.8
        -196 + (-183.4 - (-196)) * (2 / 3),             // 6: -187.6
        -183.4, -183.4,                                  // 7-8: static
        -170.4,                                          // 9
        -166.1,                                          // 10
        -166.1 + (-88.7 - (-166.1)) * (1 / 3),          // 11: -140.3
        -166.1 + (-88.7 - (-166.1)) * (2 / 3),          // 12: -114.5
        -88.7                                            // 13
    ];

    // ====== ty LUT (Matrix ty, 14 帧) ======
    const tyLUT: number[] = [
        -136, -136, -136, -136,                          // 0-3: static
        -131.1,                                          // 4
        -131.1 + (-129.75 - (-131.1)) * (1 / 3),        // 5: -130.65
        -131.1 + (-129.75 - (-131.1)) * (2 / 3),        // 6: -130.2
        -129.75, -129.75,                                // 7-8: static
        -135.85,                                         // 9
        -137.9,                                          // 10
        -137.9 + (-136.5 - (-137.9)) * (1 / 3),         // 11: -137.43
        -137.9 + (-136.5 - (-137.9)) * (2 / 3),         // 12: -136.97
        -136.5                                           // 13
    ];

    // ====== 预计算位置偏移 LUT ======
    // offsetX[f] = scaleLUT[f] * TEXT_CENTER_X + txLUT[f]
    // offsetY[f] = scaleLUT[f] * TEXT_CENTER_Y + tyLUT[f]
    // 这是 SWF 文本字段中心相对于 MC 原点的偏移（gameworld 坐标系）

    function buildOffsetLUT(centerCoord: number, scaleLut: number[], translateLut: number[]): number[] {
        const lut: number[] = [];
        for (let i = 0; i < 14; i++) {
            lut[i] = scaleLut[i] * centerCoord + translateLut[i];
        }
        return lut;
    }

    export const offsetXLUT: number[] = buildOffsetLUT(TEXT_CENTER_X, scaleLUT, txLUT);
    export const offsetYLUT: number[] = buildOffsetLUT(TEXT_CENTER_Y, scaleLUT, tyLUT);

    /**
     * Alpha：Flash SWF 中无显式 alpha 变化。
     * 保持全程 1.0，与 Flash 行为一致。
     * 缩小阶段（frame 10-13）的视觉消散完全靠 scale 实现。
     */
    export function getAlpha(frame: number): number {
        return 1.0;
    }
}
