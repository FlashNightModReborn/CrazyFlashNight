/// <reference path="types.ts" />
/// <reference path="camera.ts" />
/// <reference path="animation.ts" />
/// <reference path="parser.ts" />

namespace HitNumber {
    const POSITION_OFFSET = 60;
    const MAX_ACTIVE = 80;
    const TOTAL_FRAMES = 14;
    const MARGIN = 100;

    // ======== 混合密度管理 ========
    const DENSITY_LOW = 8;
    const MERGE_DIST = 40;
    const PULSE_REWIND = 4;

    // ======== 段数递增动画 ========
    /** 递增动画最大持续帧数（避免大段数计数太久） */
    const COUNT_ANIM_MAX_FRAMES = 8;

    const _active: ActiveEntry[] = [];
    let _activeCount = 0;

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

            if (highDensity) {
                const mi = findMergeTarget(rawX, rawY);
                if (mi >= 0) {
                    const existing = _active[mi];
                    existing.targetDmg += dmg;
                    existing.targetHits++;
                    // displayHits 不变——tick 时逐帧递增
                    existing.packed = +parts[3];
                    const et = unescField(parts[4]);
                    const ee = unescField(parts[5]);
                    if (et) existing.efText = et;
                    if (ee) existing.efEmoji = ee;
                    const ls = +parts[6];
                    const sa = +parts[7];
                    if (ls > 0) existing.lifeSteal += ls;
                    if (sa > 0) existing.shieldAbsorb += sa;
                    existing.frame = Math.max(0, existing.frame - PULSE_REWIND);
                    continue;
                }
            }

            if (_activeCount >= MAX_ACTIVE) continue;
            const entry: ActiveEntry = {
                worldX: rawX + (Math.random() - 0.5) * POSITION_OFFSET * 2,
                worldY: rawY + (Math.random() - 0.5) * POSITION_OFFSET * 2,
                rawX: rawX,
                rawY: rawY,
                targetDmg: dmg,
                displayDmg: dmg,
                packed: +parts[3],
                efText: unescField(parts[4]),
                efEmoji: unescField(parts[5]),
                lifeSteal: +parts[6],
                shieldAbsorb: +parts[7],
                frame: 0,
                targetHits: 1,
                displayHits: 1
            };
            _active[_activeCount++] = entry;
        }
    }

    /**
     * 每帧调用。输出 stride=12：
     * stgX,stgY,combinedScale,alpha,combinedBlur,damage,packed,efText,efEmoji,lifeSteal,shieldAbsorb,displayHits
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

            // 段数递增动画：displayHits 追赶 targetHits
            if (e.displayHits < e.targetHits) {
                const hitDelta = e.targetHits - e.displayHits;
                const hitRate = hitDelta <= COUNT_ANIM_MAX_FRAMES
                    ? 1
                    : Math.ceil(hitDelta / COUNT_ANIM_MAX_FRAMES);
                e.displayHits = Math.min(e.displayHits + hitRate, e.targetHits);
            }

            // 伤害递增动画：displayDmg 追赶 targetDmg（同步节奏）
            if (e.displayDmg < e.targetDmg) {
                const dmgDelta = e.targetDmg - e.displayDmg;
                const dmgRate = dmgDelta <= COUNT_ANIM_MAX_FRAMES
                    ? Math.ceil(dmgDelta / COUNT_ANIM_MAX_FRAMES)
                    : Math.ceil(dmgDelta / COUNT_ANIM_MAX_FRAMES);
                e.displayDmg = Math.min(e.displayDmg + dmgRate, e.targetDmg);
            }

            const textX = e.worldX + offsetXLUT[f];
            const textY = e.worldY + offsetYLUT[f];

            const stgX = cam.gx + textX * cam.sx;
            const stgY = cam.gy + textY * cam.sx;

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
                      (e.displayDmg | 0) + "," + e.packed + "," +
                      e.efText + "," + e.efEmoji + "," +
                      e.lifeSteal + "," + e.shieldAbsorb + "," +
                      e.displayHits;

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
