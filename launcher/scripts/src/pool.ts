/// <reference path="types.ts" />
/// <reference path="camera.ts" />
/// <reference path="animation.ts" />
/// <reference path="parser.ts" />

namespace HitNumber {
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

    const _active: ActiveEntry[] = [];
    let _activeCount = 0;

    /**
     * 在活跃列表中查找同目标条目（rawX/rawY 距离 < MERGE_DIST）
     * 返回索引，未找到返回 -1
     */
    function findMergeTarget(rawX: number, rawY: number): number {
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
    export function spawnBatch(raw: string): void {
        if (!raw || raw.length === 0) return;
        const entries = raw.split(";");
        const highDensity = _activeCount > DENSITY_LOW;

        for (let i = 0; i < entries.length; i++) {
            const parts = entries[i].split("|");
            if (parts.length < 8) continue;

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
                    const et = unescField(parts[4]);
                    const ee = unescField(parts[5]);
                    if (et) existing.efText = et;
                    if (ee) existing.efEmoji = ee;
                    const ls = +parts[6];
                    const sa = +parts[7];
                    if (ls > 0) existing.lifeSteal += ls;
                    if (sa > 0) existing.shieldAbsorb += sa;
                    // 脉冲：回退动画帧（产生重新放大效果）
                    existing.frame = Math.max(0, existing.frame - PULSE_REWIND);
                    continue;
                }
            }

            // 新建条目
            if (_activeCount >= MAX_ACTIVE) continue;
            const entry: ActiveEntry = {
                worldX: rawX + (Math.random() - 0.5) * POSITION_OFFSET * 2,
                worldY: rawY + (Math.random() - 0.5) * POSITION_OFFSET * 2,
                rawX: rawX,
                rawY: rawY,
                damage: dmg,
                packed: +parts[3],
                efText: unescField(parts[4]),
                efEmoji: unescField(parts[5]),
                lifeSteal: +parts[6],
                shieldAbsorb: +parts[7],
                frame: 0,
                hitCount: 1
            };
            _active[_activeCount++] = entry;
        }
    }

    /**
     * 每帧调用一次（由 Flash frame 消息驱动）
     *
     * 输出格式（stride=12）：
     *   stgX,stgY,combinedScale,alpha,combinedBlur,damage,packed,efText,efEmoji,lifeSteal,shieldAbsorb,hitCount
     */
    export function tick(): string {
        if (_activeCount === 0) return "";

        const cam = camera;
        let result = "";
        let writeIdx = 0;

        for (let i = 0; i < _activeCount; i++) {
            const e = _active[i];
            const f = e.frame;

            if (f >= TOTAL_FRAMES) continue;

            // 文本中心 = MC 原点 + SWF Matrix 偏移
            const textX = e.worldX + offsetXLUT[f];
            const textY = e.worldY + offsetYLUT[f];

            const stgX = cam.gx + textX * cam.sx;
            const stgY = cam.gy + textY * cam.sx;

            // 视口外裁剪
            if (stgX < -MARGIN || stgX > STAGE_W + MARGIN ||
                stgY < -MARGIN || stgY > STAGE_H + MARGIN) {
                e.frame = f + 1;
                if (f + 1 < TOTAL_FRAMES) _active[writeIdx++] = e;
                continue;
            }

            const combinedScale = scaleLUT[f] * cam.sx;
            const alpha = getAlpha(f);
            const combinedBlur = blurLUT[f] * cam.sx;

            if (result.length > 0) result += ";";
            result += stgX + "," + stgY + "," +
                      combinedScale + "," + alpha + "," + combinedBlur + "," +
                      e.damage + "," + e.packed + "," +
                      e.efText + "," + e.efEmoji + "," +
                      e.lifeSteal + "," + e.shieldAbsorb + "," +
                      e.hitCount;

            e.frame = f + 1;
            if (f + 1 < TOTAL_FRAMES) _active[writeIdx++] = e;
        }

        _activeCount = writeIdx;
        return result;
    }

    export function reset(): void {
        _activeCount = 0;
    }

    export function activeCount(): number {
        return _activeCount;
    }
}
