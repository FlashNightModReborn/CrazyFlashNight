"use strict";
/// <reference path="types.ts" />
var HitNumber;
(function (HitNumber) {
    /** Flash 舞台固定尺寸（FlashCoordinateMapper 构造参数确认） */
    HitNumber.STAGE_W = 1024;
    HitNumber.STAGE_H = 576;
    HitNumber.camera = {
        gx: 0, gy: 0, sx: 1
    };
    /**
     * 由 C# FrameTask 调用，传入管道分隔字符串
     * 格式: "gx|gy|sx"（3 段）
     */
    function updateCameraRaw(raw) {
        const parts = raw.split("|");
        HitNumber.camera.gx = +parts[0];
        HitNumber.camera.gy = +parts[1];
        HitNumber.camera.sx = +parts[2];
    }
    HitNumber.updateCameraRaw = updateCameraRaw;
})(HitNumber || (HitNumber = {}));
/// <reference path="types.ts" />
var HitNumber;
(function (HitNumber) {
    /** Flash 侧 COLOR_TABLE 的镜像（HitNumberBatchProcessor.as:110） */
    HitNumber.COLOR_TABLE = [
        "#FFFFFF", "#FF0000", "#FFCC00", "#660033", "#4A0099",
        "#AC99FF", "#0099FF", "#7F0000", "#7F6A00", "#FF7F7F", "#FFE770"
    ];
    // 效果标志位常量（DamageResult.as bits 0-8）
    HitNumber.EF_CRUMBLE = 1;
    HitNumber.EF_TOXIC = 2;
    HitNumber.EF_EXECUTE = 4;
    HitNumber.EF_DMG_TYPE_LABEL = 8;
    HitNumber.EF_CRUSH_LABEL = 16;
    HitNumber.EF_LIFESTEAL = 32;
    HitNumber.EF_IS_ENEMY = 128;
    HitNumber.EF_SHIELD = 256;
    // packed 编码（DamageResult.as:462-469）：
    //   bits 0-8:   efFlags (9 bits)
    //   bit  9:     isMISS
    //   bits 10-17: damageSize (0-255)
    //   bits 18-21: colorId (0-15)
    function unpackFlags(packed) { return packed & 511; }
    HitNumber.unpackFlags = unpackFlags;
    function unpackIsMISS(packed) { return ((packed >> 9) & 1) !== 0; }
    HitNumber.unpackIsMISS = unpackIsMISS;
    function unpackSize(packed) { return (packed >> 10) & 255; }
    HitNumber.unpackSize = unpackSize;
    function unpackColorId(packed) { return (packed >> 18) & 15; }
    HitNumber.unpackColorId = unpackColorId;
    /**
     * 协议字段反序列化。
     *
     * 当前取值域审计结果：efText/efEmoji 均不含分隔符，
     * AS2 侧 safeField 仅做 null→空串，不做转义。
     * 此函数保留接口签名，当前为直通。
     *
     * 若未来协议需要转义，在此处实现反转义即可，
     * 无需修改 AS2 热路径。
     */
    function unescField(s) {
        if (!s)
            return "";
        return s;
    }
    HitNumber.unescField = unescField;
})(HitNumber || (HitNumber = {}));
/// <reference path="types.ts" />
/// <reference path="camera.ts" />
/// <reference path="animation.ts" />
/// <reference path="parser.ts" />
var HitNumber;
(function (HitNumber) {
    /** 随机位置偏移量（像素），与 Flash 侧 HitNumberSystem 一致 */
    const POSITION_OFFSET = 60;
    /** 最大同时活跃数字数 */
    const MAX_ACTIVE = 80;
    /** 总可见帧数 */
    const TOTAL_FRAMES = 14;
    /** 视口外裁剪边距 */
    const MARGIN = 100;
    // ======== 混合密度管理 ========
    /** 低密度阈值：活跃数 ≤ 此值时每个 hit 独立显示 */
    const DENSITY_LOW = 8;
    /** 同目标合并距离阈值（gameworld 像素） */
    const MERGE_DIST = 40;
    /** 合并时动画回退帧数（产生"脉冲"放大效果） */
    const PULSE_REWIND = 4;
    const _active = [];
    let _activeCount = 0;
    /**
     * 在活跃列表中查找同目标条目（rawX/rawY 距离 < MERGE_DIST）
     * 返回索引，未找到返回 -1
     */
    function findMergeTarget(rawX, rawY) {
        for (let i = 0; i < _activeCount; i++) {
            const e = _active[i];
            const dx = e.rawX - rawX;
            const dy = e.rawY - rawY;
            if (dx * dx + dy * dy < MERGE_DIST * MERGE_DIST) {
                return i;
            }
        }
        return -1;
    }
    /**
     * 由 C# FrameTask 调用
     * 格式: "v|x|y|p|et|ee|ls|sa;..."
     */
    function spawnBatch(raw) {
        if (!raw || raw.length === 0)
            return;
        const entries = raw.split(";");
        const highDensity = _activeCount > DENSITY_LOW;
        for (let i = 0; i < entries.length; i++) {
            const parts = entries[i].split("|");
            if (parts.length < 8)
                continue;
            const rawX = +parts[1];
            const rawY = +parts[2];
            const dmg = +parts[0];
            // 高密度时尝试合并同目标
            if (highDensity) {
                const mi = findMergeTarget(rawX, rawY);
                if (mi >= 0) {
                    const existing = _active[mi];
                    existing.damage += dmg;
                    existing.hitCount++;
                    // 更新效果标签为最新
                    existing.packed = +parts[3];
                    const et = HitNumber.unescField(parts[4]);
                    const ee = HitNumber.unescField(parts[5]);
                    if (et)
                        existing.efText = et;
                    if (ee)
                        existing.efEmoji = ee;
                    const ls = +parts[6];
                    const sa = +parts[7];
                    if (ls > 0)
                        existing.lifeSteal += ls;
                    if (sa > 0)
                        existing.shieldAbsorb += sa;
                    // 脉冲：回退动画帧（产生重新放大效果）
                    existing.frame = Math.max(0, existing.frame - PULSE_REWIND);
                    continue;
                }
            }
            // 新建条目
            if (_activeCount >= MAX_ACTIVE)
                continue;
            const entry = {
                worldX: rawX + (Math.random() - 0.5) * POSITION_OFFSET * 2,
                worldY: rawY + (Math.random() - 0.5) * POSITION_OFFSET * 2,
                rawX: rawX,
                rawY: rawY,
                damage: dmg,
                packed: +parts[3],
                efText: HitNumber.unescField(parts[4]),
                efEmoji: HitNumber.unescField(parts[5]),
                lifeSteal: +parts[6],
                shieldAbsorb: +parts[7],
                frame: 0,
                hitCount: 1
            };
            _active[_activeCount++] = entry;
        }
    }
    HitNumber.spawnBatch = spawnBatch;
    /**
     * 每帧调用一次（由 Flash frame 消息驱动）
     *
     * 输出格式（stride=12）：
     *   stgX,stgY,combinedScale,alpha,combinedBlur,damage,packed,efText,efEmoji,lifeSteal,shieldAbsorb,hitCount
     */
    function tick() {
        if (_activeCount === 0)
            return "";
        const cam = HitNumber.camera;
        let result = "";
        let writeIdx = 0;
        for (let i = 0; i < _activeCount; i++) {
            const e = _active[i];
            const f = e.frame;
            if (f >= TOTAL_FRAMES)
                continue;
            // 文本中心 = MC 原点 + SWF Matrix 偏移
            const textX = e.worldX + HitNumber.offsetXLUT[f];
            const textY = e.worldY + HitNumber.offsetYLUT[f];
            const stgX = cam.gx + textX * cam.sx;
            const stgY = cam.gy + textY * cam.sx;
            // 视口外裁剪
            if (stgX < -MARGIN || stgX > HitNumber.STAGE_W + MARGIN ||
                stgY < -MARGIN || stgY > HitNumber.STAGE_H + MARGIN) {
                e.frame = f + 1;
                if (f + 1 < TOTAL_FRAMES)
                    _active[writeIdx++] = e;
                continue;
            }
            const combinedScale = HitNumber.scaleLUT[f] * cam.sx;
            const alpha = HitNumber.getAlpha(f);
            const combinedBlur = HitNumber.blurLUT[f] * cam.sx;
            if (result.length > 0)
                result += ";";
            result += stgX + "," + stgY + "," +
                combinedScale + "," + alpha + "," + combinedBlur + "," +
                e.damage + "," + e.packed + "," +
                e.efText + "," + e.efEmoji + "," +
                e.lifeSteal + "," + e.shieldAbsorb + "," +
                e.hitCount;
            e.frame = f + 1;
            if (f + 1 < TOTAL_FRAMES)
                _active[writeIdx++] = e;
        }
        _activeCount = writeIdx;
        return result;
    }
    HitNumber.tick = tick;
    function reset() {
        _activeCount = 0;
    }
    HitNumber.reset = reset;
    function activeCount() {
        return _activeCount;
    }
    HitNumber.activeCount = activeCount;
})(HitNumber || (HitNumber = {}));
/// <reference path="camera.ts" />
/// <reference path="animation.ts" />
/// <reference path="parser.ts" />
/// <reference path="pool.ts" />
/// <reference path="types.ts" />
var HitNumber;
(function (HitNumber) {
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
    HitNumber.scaleLUT = [
        1.3176, 1.3176, 1.3176, 1.3176, // 0-3: static
        1.0687, // 4
        1.0687 + (1.0 - 1.0687) * (1 / 3), // 5
        1.0687 + (1.0 - 1.0687) * (2 / 3), // 6
        1.0, 1.0, // 7-8: static
        0.9291, // 9
        0.9056, // 10
        0.9056 + (0.3280 - 0.9056) * (1 / 3), // 11
        0.9056 + (0.3280 - 0.9056) * (2 / 3), // 12
        0.3280 // 13
    ];
    // ====== blur LUT (14 帧, GlowFilter 偏移半径) ======
    HitNumber.blurLUT = [
        4, 4, 4, 4, // 0-3
        3, 3, 3, 3, 3, // 4-8
        2, // 9
        2, // 10
        2 + (1 - 2) * (1 / 3), // 11
        2 + (1 - 2) * (2 / 3), // 12
        1 // 13
    ];
    // ====== tx LUT (Matrix tx, 14 帧) ======
    const txLUT = [
        -241.65, -241.65, -241.65, -241.65, // 0-3: static
        -196, // 4
        -196 + (-183.4 - (-196)) * (1 / 3), // 5: -191.8
        -196 + (-183.4 - (-196)) * (2 / 3), // 6: -187.6
        -183.4, -183.4, // 7-8: static
        -170.4, // 9
        -166.1, // 10
        -166.1 + (-88.7 - (-166.1)) * (1 / 3), // 11: -140.3
        -166.1 + (-88.7 - (-166.1)) * (2 / 3), // 12: -114.5
        -88.7 // 13
    ];
    // ====== ty LUT (Matrix ty, 14 帧) ======
    const tyLUT = [
        -136, -136, -136, -136, // 0-3: static
        -131.1, // 4
        -131.1 + (-129.75 - (-131.1)) * (1 / 3), // 5: -130.65
        -131.1 + (-129.75 - (-131.1)) * (2 / 3), // 6: -130.2
        -129.75, -129.75, // 7-8: static
        -135.85, // 9
        -137.9, // 10
        -137.9 + (-136.5 - (-137.9)) * (1 / 3), // 11: -137.43
        -137.9 + (-136.5 - (-137.9)) * (2 / 3), // 12: -136.97
        -136.5 // 13
    ];
    // ====== 预计算位置偏移 LUT ======
    // offsetX[f] = scaleLUT[f] * TEXT_CENTER_X + txLUT[f]
    // offsetY[f] = scaleLUT[f] * TEXT_CENTER_Y + tyLUT[f]
    // 这是 SWF 文本字段中心相对于 MC 原点的偏移（gameworld 坐标系）
    function buildOffsetLUT(centerCoord, scaleLut, translateLut) {
        const lut = [];
        for (let i = 0; i < 14; i++) {
            lut[i] = scaleLut[i] * centerCoord + translateLut[i];
        }
        return lut;
    }
    HitNumber.offsetXLUT = buildOffsetLUT(TEXT_CENTER_X, HitNumber.scaleLUT, txLUT);
    HitNumber.offsetYLUT = buildOffsetLUT(TEXT_CENTER_Y, HitNumber.scaleLUT, tyLUT);
    /**
     * Alpha：Flash SWF 中无显式 alpha 变化。
     * 保持全程 1.0，与 Flash 行为一致。
     * 缩小阶段（frame 10-13）的视觉消散完全靠 scale 实现。
     */
    function getAlpha(frame) {
        return 1.0;
    }
    HitNumber.getAlpha = getAlpha;
})(HitNumber || (HitNumber = {}));
