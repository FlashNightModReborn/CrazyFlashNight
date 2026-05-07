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

    // ======== Aggregator（unit 头顶累计总伤数字）========
    /** aggregator 弹入完成后停留在此帧（scale=1.0 稳态显示）。命中刷新时 PULSE_REWIND 回到此帧之前 */
    const AGGREGATOR_HOLD_FRAME = 7;
    /** 静默超过此帧数后 aggregator 才开始走衰退动画（≈30 帧 ≈ 1.25s @ 24fps） */
    const AGGREGATOR_QUIET_FRAMES = 30;
    /** 屏幕上同时存活的 aggregator 上限。超出时新 unit 命中合并到最近的现有 aggregator（uid 重定向） */
    const MAX_AGGREGATORS = 8;

    // ======== 命中脉动（pulseTimer）========
    /** 命中瞬间脉动持续帧数。tick 时 pulseTimer-- 线性衰减回 0 */
    const PULSE_DURATION = 6;
    /** 满幅脉动时额外字号加成（0.5 = +50%）。衰减到 0 时回归 1.0× */
    const PULSE_AMP = 0.5;

    // ======== packed bit mask ========
    /** efFlags 占 bits 0-8 (9 bits) */
    const PACKED_EFFLAGS_MASK = 0x1FF;
    /** efFlags + isMISS = bits 0-9，清零此位段保留 size/colorId/未来扩展 */
    const PACKED_LOW10_MASK = 0x3FF;
    /** isMISS = bit 9 */
    const PACKED_MISS_MASK = 0x200;

    // ======== efFlag 动效显示策略（短期反馈 + 长期占比的时间维度调和）========
    /** ratio < FLOOR：标签 target=0（最终消失） */
    const VISIBILITY_FLOOR = 0.10;
    /** ratio ≥ CEIL：标签 target=1.0（满字号），中间线性插值 */
    const VISIBILITY_CEIL = 0.50;
    /** display_scale 每帧向 target 线性追赶的步长（0.05 ≈ 20 帧 / 0.83s 从 1.0 衰减到 0） */
    const DECAY_STEP = 0.05;
    /** EF_EXECUTE = bit 2（一击必杀关键反馈，永远豁免衰减，target 恒为 1.0） */
    const EF_EXECUTE_BIT = 2;

    // ======== 颜色 RGB 插值（boost + 衰减回 dominant）========
    // 与 HitNumberBatchProcessor.as / HitNumberOverlay.cs / parser.ts 的 COLOR_TABLE 镜像
    const COLOR_TABLE_RGB: number[][] = [
        [0xFF, 0xFF, 0xFF], // 0: 白
        [0xFF, 0x00, 0x00], // 1: 红
        [0xFF, 0xCC, 0x00], // 2: 黄
        [0x66, 0x00, 0x33], // 3: 紫红
        [0x4A, 0x00, 0x99], // 4: 紫蓝
        [0xAC, 0x99, 0xFF], // 5: 浅紫
        [0x00, 0x99, 0xFF], // 6: 蓝
        [0x7F, 0x00, 0x00], // 7: 暗红
        [0x7F, 0x6A, 0x00], // 8: 暗黄
        [0xFF, 0x7F, 0x7F], // 9: 浅红
        [0xFF, 0xE7, 0x70]  // 10: 浅黄
    ];
    /** RGB 每帧向 target 移动比例（指数衰减）：0.15 ≈ 8 帧达成 ~75% 接近，自然柔和 */
    const COLOR_DECAY_RATIO = 0.15;
    const COLOR_TABLE_LENGTH = 11;

    function getColorRGB(cid: number): number[] {
        return cid >= 0 && cid < COLOR_TABLE_LENGTH ? COLOR_TABLE_RGB[cid] : COLOR_TABLE_RGB[0];
    }

    function toHexByte(v: number): string {
        let x = Math.round(v);
        if (x < 0) x = 0;
        else if (x > 255) x = 255;
        const s = x.toString(16);
        return s.length === 1 ? "0" + s : s;
    }

    let _aggregatorCount = 0;

    /** 找当前 _active 中距离 (rawX, rawY) 最近的 aggregator entry。aggregator 满员时使用 */
    function findNearestAggregator(rawX: number, rawY: number): ActiveEntry | null {
        let best: ActiveEntry | null = null;
        let bestDist = Infinity;
        for (let i = 0; i < _activeCount; i++) {
            const e = _active[i];
            if (!e.isAggregator) continue;
            const dx = e.rawX - rawX;
            const dy = e.rawY - rawY;
            const d = dx * dx + dy * dy;
            if (d < bestDist) {
                best = e;
                bestDist = d;
            }
        }
        return best;
    }

    /**
     * 把 (parts, dmg) 累加到 aggregator。混伤合并语义（方案 E）：
     *   - MISS 段（dmg=0 + isMISS bit）→ 完全跳过（不入 aggregator，避免污染累计显示）
     *   - efFlags（bits 0-8）→ OR 累积，保留这套连段触发过的所有效果标签
     *   - isMISS（bit 9）→ aggregator packed 永远清 0
     *   - size/colorId（bits 10-21）→ 追最大单段伤害（暴击段视觉接管）
     *   - 视觉脉动：pulseTimer = PULSE_DURATION（独立瞬时放大动效）
     */
    function pulseAggregator(e: ActiveEntry, parts: string[], dmg: number, rawX: number, rawY: number): void {
        const newPacked = +parts[3];
        // MISS 过滤：MISS 段不入 aggregator（既不累加伤害也不刷状态、不脉动）
        if ((newPacked & PACKED_MISS_MASK) !== 0) return;

        e.targetDmg += dmg;
        e.targetHits++;

        // efFlags OR 累积；isMISS 永远清 0
        const newFlags = newPacked & PACKED_EFFLAGS_MASK;
        const mergedFlags = (e.packed | newPacked) & PACKED_EFFLAGS_MASK;
        // 按 flag 累加伤害量 + boost 显示字号
        // 同一段伤害可同时触发多个 flag（毒+暴击），都计入各自槽位
        // 命中触发的 flag 字号瞬间刷满 1.0（即时反馈），后续 tick 衰减到占比对应字号
        for (let bit = 0; bit < 9; bit++) {
            if ((newFlags & (1 << bit)) !== 0) {
                e.efFlagDmgSum[bit] += dmg;
                e.displayFlagScales[bit] = 1.0;
            }
        }
        // size/colorId 高位：暴击段（dmg 超过历史最大）时刷新 packed，否则保留
        let highBits: number;
        if (dmg > e.maxSegmentDmg) {
            e.maxSegmentDmg = dmg;
            highBits = newPacked & ~PACKED_LOW10_MASK;
        } else {
            highBits = e.packed & ~PACKED_LOW10_MASK;
        }
        e.packed = mergedFlags | highBits;

        // 每次命中都 boost displayRGB 到该段色（短期反馈：玩家立即看到当前属性）
        // 后续 tick 帧向 dominant 指数衰减，长期回归输出贡献占比对应色
        const newColorId = (newPacked >> 18) & 15;
        const boostRgb = getColorRGB(newColorId);
        e.displayR = boostRgb[0];
        e.displayG = boostRgb[1];
        e.displayB = boostRgb[2];

        // colorIdDmgSum 累加（用于算 dominant）
        if (newColorId < COLOR_TABLE_LENGTH) {
            e.colorIdDmgSum[newColorId] += dmg;
        }

        const et = unescField(parts[4]);
        const ee = unescField(parts[5]);
        if (et) {
            e.efText = et;
            // EF_DMG_TYPE_LABEL (bit 3) 触发时同步记录该段 colorId，渲染端据此决定标签颜色
            // EF_CRUSH_LABEL (bit 4) 颜色固定 #66BCF5，无需 efTextColorId
            if ((newPacked & 8) !== 0) {
                e.efTextColorId = (newPacked >> 18) & 15;
            }
        }
        if (ee) e.efEmoji = ee;
        const ls = +parts[6];
        const sa = +parts[7];
        if (ls > 0) e.lifeSteal += ls;
        if (sa > 0) e.shieldAbsorb += sa;

        // 位置追踪：跟随最新被击中位置
        e.rawX = rawX;
        e.rawY = rawY;
        e.worldX = rawX;
        e.worldY = rawY;
        e.silentFrames = 0;

        // 视觉脉动：独立瞬时放大动效（不依赖 frame 系统）
        e.pulseTimer = PULSE_DURATION;
        // 保留原 frame 脉动（弹入动画反馈，与 pulseTimer 叠加）
        e.frame = Math.max(0, e.frame - PULSE_REWIND);
    }

    /** aggregator 死亡时清理 _unitMap：可能多个 uid 重定向到同一 aggregator，全部删除 */
    function cleanupDeadAggregator(e: ActiveEntry): void {
        for (const uid in _unitMap) {
            if (_unitMap[uid] === e) delete _unitMap[uid];
        }
        _aggregatorCount--;
    }

    const _active: ActiveEntry[] = [];
    let _activeCount = 0;

    // unitId → entry 引用映射。无原型对象避免 __proto__ / constructor 污染。
    // 存引用而非索引：tick 中 swap-remove 不动 map，唯一同步点是 entry 死亡时 delete。
    let _unitMap: { [uid: string]: ActiveEntry } = Object.create(null);

    function findMergeTargetByDistance(rawX: number, rawY: number): number {
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

    function mergeInto(existing: ActiveEntry, parts: string[], dmg: number): void {
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
    }

    /**
     * 单轨 aggregator 模型：
     *
     *   每次 unitId 命中 → 累加到该 unit 的 aggregator entry
     *     - 首次见 uid → 创建新 aggregator（超过 MAX_AGGREGATORS 时合并到最近的，uid 重定向）
     *     - 已存在 → 数据累加 + 弹入脉动 + 位置追踪
     *
     *   命中反馈：
     *     - 弹入动画（frame 0→7 弹入到稳态）
     *     - PULSE_REWIND 命中时 frame 回退 → 弹一下
     *     - displayDmg / displayHits 跳数动画（数字逐帧追上目标值）
     *     - 字号回归 baseScale × 1.0（不放大，避免怪海堆积）
     *
     *   旧协议（无 uid）：保留原距离合并 fallback
     */
    export function spawnBatch(raw: string): void {
        if (!raw || raw.length === 0) return;
        const entries = raw.split(";");

        // 本批次内同 uid 临时锚点（避免同帧多段重复创建 aggregator）
        const sameFrameAggregators: { [uid: string]: ActiveEntry } = Object.create(null);

        for (let i = 0; i < entries.length; i++) {
            const parts = entries[i].split("|");
            if (parts.length < 8) continue;

            const rawX = +parts[1];
            const rawY = +parts[2];
            const dmg = +parts[0];
            const uid = parts.length >= 9 ? parts[8] : "";

            // === 新协议路径：aggregator-only ===
            if (uid !== "") {
                let aggregator = _unitMap[uid];
                if (aggregator === undefined) aggregator = sameFrameAggregators[uid];

                if (aggregator !== undefined) {
                    pulseAggregator(aggregator, parts, dmg, rawX, rawY);
                    continue;
                }

                // 首次见此 uid → 检查 aggregator 上限
                if (_aggregatorCount >= MAX_AGGREGATORS) {
                    // 怪海场景：合并到最近的现有 aggregator + uid 重定向
                    // 屏幕上仍然只有 MAX_AGGREGATORS 个数字，新 unit 的伤害融入邻居
                    const nearest = findNearestAggregator(rawX, rawY);
                    if (nearest !== null) {
                        pulseAggregator(nearest, parts, dmg, rawX, rawY);
                        // uid 重定向：本 unit 后续命中也走这个 aggregator
                        // _unitMap 多 key 指向同一 aggregator；death cleanup 全清
                        _unitMap[uid] = nearest;
                        continue;
                    }
                    // 兜底（理论不会触发：上限 > 0 必有 aggregator 存在）
                    continue;
                }

                // 首次创建：MISS 过滤（首段就 miss = 什么都没发生，不创建 aggregator）
                const firstPacked = +parts[3];
                if ((firstPacked & PACKED_MISS_MASK) !== 0) continue;

                if (_activeCount >= MAX_ACTIVE) continue;
                // efFlagDmgSum + displayFlagScales 初始化：
                // - 首段触发的 flag：dmg 计入累计，displayFlagScale = 1.0（即时反馈）
                // - 未触发的 flag：累计 0，display 0
                const initFlagSums: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0];
                const initDisplayScales: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0];
                const initFlags = firstPacked & PACKED_EFFLAGS_MASK;
                for (let bit = 0; bit < 9; bit++) {
                    if ((initFlags & (1 << bit)) !== 0) {
                        initFlagSums[bit] = dmg;
                        initDisplayScales[bit] = 1.0;
                    }
                }
                // colorIdDmgSum + displayRGB 初始化
                const initColorSums: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
                const firstCid = (firstPacked >> 18) & 15;
                if (firstCid < COLOR_TABLE_LENGTH) initColorSums[firstCid] = dmg;
                const firstRgb = getColorRGB(firstCid);
                const aggEntry: ActiveEntry = {
                    worldX: rawX,  // aggregator 不含 ±60 偏移，钉在 unit 位置
                    worldY: rawY,
                    rawX: rawX,
                    rawY: rawY,
                    targetDmg: dmg,
                    displayDmg: dmg,
                    packed: firstPacked & ~PACKED_MISS_MASK,  // 防御：清 isMISS（即便上面已过滤）
                    efText: unescField(parts[4]),
                    efEmoji: unescField(parts[5]),
                    lifeSteal: +parts[6],
                    shieldAbsorb: +parts[7],
                    frame: 0,
                    targetHits: 1,
                    displayHits: 1,
                    unitId: uid,
                    isAggregator: true,
                    silentFrames: 0,
                    pulseTimer: PULSE_DURATION,  // 首次创建即给一次脉动反馈
                    maxSegmentDmg: dmg,          // 初始最大段就是首段
                    efFlagDmgSum: initFlagSums,
                    displayFlagScales: initDisplayScales,
                    colorIdDmgSum: initColorSums,
                    displayR: firstRgb[0],
                    displayG: firstRgb[1],
                    displayB: firstRgb[2],
                    // 首段如果含 EF_DMG_TYPE_LABEL (bit 3) → efTextColorId = firstCid，否则用 firstCid 占位
                    efTextColorId: firstCid
                };
                _active[_activeCount++] = aggEntry;
                sameFrameAggregators[uid] = aggEntry;
                _aggregatorCount++;
                continue;
            }

            // === 旧协议路径（无 uid）：原距离合并 fallback ===
            const highDensity = _activeCount > DENSITY_LOW;
            if (highDensity) {
                const mi = findMergeTargetByDistance(rawX, rawY);
                if (mi >= 0) {
                    mergeInto(_active[mi], parts, dmg);
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
                displayHits: 1,
                unitId: "",
                isAggregator: false,
                silentFrames: 0,
                pulseTimer: 0,        // 旧协议 entry 不脉动
                maxSegmentDmg: 0,     // 不使用
                efFlagDmgSum: [0, 0, 0, 0, 0, 0, 0, 0, 0],     // 占位（仅 aggregator 用）
                displayFlagScales: [1, 1, 1, 1, 1, 1, 1, 1, 1], // 旧协议：全 1.0（输出全 level 9 满字号）
                colorIdDmgSum: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],  // 占位（仅 aggregator 用）
                displayR: 0, displayG: 0, displayB: 0,           // 占位，旧协议输出空 hex 字段，C# fallback 用 colorId
                efTextColorId: 0                                  // 占位（旧协议不输出 fields[14]，C# fallback 用 mainColor）
            };
            _active[_activeCount++] = entry;
        }

        // 批次结束：本帧创建的 aggregator 注册到 _unitMap
        for (const uid in sameFrameAggregators) {
            _unitMap[uid] = sameFrameAggregators[uid];
        }
    }

    // ======== 视觉层级（Z-order + size scaling）========
    // 旧协议距离合并 entry 字号公式：base + per_hit × min(hits, cap)
    // 新协议 aggregator 字号回归 baseScale × 1.0（不放大），靠 PULSE_REWIND + 跳数动画提供反馈
    const MERGE_SCALE_BASE = 1;
    const MERGE_SCALE_PER_HIT = 0.04;
    const MERGE_SCALE_HIT_CAP = 10;

    /**
     * 决定 entry 的下一 frame 值。
     *   - Floating / 普通：frame++
     *   - Aggregator：弹入期 frame++ → 到 HOLD_FRAME 后停留 → 静默超 QUIET 才推进衰退
     */
    function advanceFrame(e: ActiveEntry, f: number): number {
        if (e.isAggregator) {
            e.silentFrames++;
            if (f < AGGREGATOR_HOLD_FRAME) return f + 1;
            if (e.silentFrames >= AGGREGATOR_QUIET_FRAMES) return f + 1;
            return f;  // 稳态停留
        }
        return f + 1;
    }

    /**
     * 每帧调用。输出 stride=12：
     * stgX,stgY,combinedScale,alpha,combinedBlur,damage,packed,efText,efEmoji,lifeSteal,shieldAbsorb,displayHits
     *
     * 视觉层级：
     *   - Aggregator / 距离合并的 hits>1 → resultHigh → 最上层
     *   - 旧协议独立 entry → resultLow → 垫底
     *   - 字号统一 baseScale × 1.0（不放大，避免怪海堆积）；旧协议距离合并按 hits 微放大保留原行为
     */
    export function tick(): string {
        if (_activeCount === 0) return "";

        const cam = camera;
        let resultLow = "";
        let resultHigh = "";
        let writeIdx = 0;

        for (let i = 0; i < _activeCount; i++) {
            const e = _active[i];
            const f = e.frame;

            if (f >= TOTAL_FRAMES) {
                if (e.isAggregator) {
                    cleanupDeadAggregator(e);
                } else if (e.unitId !== "" && _unitMap[e.unitId] === e) {
                    delete _unitMap[e.unitId];
                }
                continue;
            }

            // 段数递增动画
            if (e.displayHits < e.targetHits) {
                const hitDelta = e.targetHits - e.displayHits;
                const hitRate = hitDelta <= COUNT_ANIM_MAX_FRAMES
                    ? 1
                    : Math.ceil(hitDelta / COUNT_ANIM_MAX_FRAMES);
                e.displayHits = Math.min(e.displayHits + hitRate, e.targetHits);
            }

            // 伤害递增动画
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
                const nf = advanceFrame(e, f);
                e.frame = nf;
                if (nf < TOTAL_FRAMES) {
                    _active[writeIdx++] = e;
                } else if (e.isAggregator) {
                    cleanupDeadAggregator(e);
                } else if (e.unitId !== "" && _unitMap[e.unitId] === e) {
                    delete _unitMap[e.unitId];
                }
                continue;
            }

            const baseScale = scaleLUT[f] * cam.sx;
            const hits = e.displayHits;
            // Aggregator 不放大；旧协议 hits>1 按 hits 微放大（保留原距离合并视觉）
            let scaleMul = 1;
            if (!e.isAggregator && hits > 1) {
                const cappedHits = hits < MERGE_SCALE_HIT_CAP ? hits : MERGE_SCALE_HIT_CAP;
                scaleMul = MERGE_SCALE_BASE + MERGE_SCALE_PER_HIT * cappedHits;
            }
            // 命中脉动：独立瞬时放大动效，每帧线性衰减（PULSE_AMP → 0）
            // 不依赖 frame 系统，所以加特林每帧命中时 pulseTimer 持续刷新 → 持续放大
            // 命中停止后 6 帧内自然回归 1.0
            if (e.pulseTimer > 0) {
                scaleMul *= 1 + PULSE_AMP * (e.pulseTimer / PULSE_DURATION);
                e.pulseTimer--;
            }
            const combinedScale = baseScale * scaleMul;
            const alpha = getAlpha(f);
            const combinedBlur = blurLUT[f] * cam.sx;

            // Aggregator: efFlag displayScale 演化 + RGB 颜色插值
            //   efFlag: target = ratio 映射（FLOOR..CEIL 线性），display 向 target 线性追赶
            //   RGB:    target = dominant colorId（colorIdDmgSum 最高者）对应 RGB
            //           display 向 target 指数衰减（COLOR_DECAY_RATIO），暴击段瞬时 boost 已在 pulseAggregator 处理
            //   旧协议路径：flag scale 固定 9，rgbHex 空字符串（C# fallback 用 colorId）
            let flagScales: string;
            let rgbHex: string;
            if (e.isAggregator && e.targetDmg > 0) {
                const totalDmg = e.targetDmg;
                let s = "";
                for (let bit = 0; bit < 9; bit++) {
                    let target: number;
                    if (bit === EF_EXECUTE_BIT) {
                        // EXECUTE 豁免：只要曾触发过（efFlagDmgSum>0）就保持 target=1.0
                        target = e.efFlagDmgSum[bit] > 0 ? 1.0 : 0;
                    } else {
                        const ratio = e.efFlagDmgSum[bit] / totalDmg;
                        if (ratio < VISIBILITY_FLOOR) target = 0;
                        else if (ratio >= VISIBILITY_CEIL) target = 1.0;
                        else target = (ratio - VISIBILITY_FLOOR) / (VISIBILITY_CEIL - VISIBILITY_FLOOR);
                    }
                    // approach: display 向 target 线性追赶
                    const cur = e.displayFlagScales[bit];
                    let next: number;
                    if (cur < target) next = cur + DECAY_STEP > target ? target : cur + DECAY_STEP;
                    else if (cur > target) next = cur - DECAY_STEP < target ? target : cur - DECAY_STEP;
                    else next = cur;
                    e.displayFlagScales[bit] = next;
                    // 编码 0-9 level：next * 9 四舍五入；< 0.05 直接为 0（接近消失即不渲染）
                    let level: number;
                    if (next < 0.05) level = 0;
                    else level = Math.round(next * 9);
                    if (level > 9) level = 9;
                    s += level;
                }
                flagScales = s;

                // RGB 颜色插值：算 dominant colorId → target RGB → display 指数衰减追赶
                let bestDmg = 0;
                let dominantCid = 0;
                for (let cid = 0; cid < COLOR_TABLE_LENGTH; cid++) {
                    if (e.colorIdDmgSum[cid] > bestDmg) {
                        bestDmg = e.colorIdDmgSum[cid];
                        dominantCid = cid;
                    }
                }
                const target = COLOR_TABLE_RGB[dominantCid];
                e.displayR += (target[0] - e.displayR) * COLOR_DECAY_RATIO;
                e.displayG += (target[1] - e.displayG) * COLOR_DECAY_RATIO;
                e.displayB += (target[2] - e.displayB) * COLOR_DECAY_RATIO;
                rgbHex = toHexByte(e.displayR) + toHexByte(e.displayG) + toHexByte(e.displayB);
            } else {
                flagScales = "999999999";  // 旧协议：所有 flag 满字号
                rgbHex = "";               // 旧协议：空字段，C# fallback 用 colorId
            }

            // EF_DMG_TYPE_LABEL 标签颜色对应的 colorId（hex 1 字符 '0'-'F'）
            // 与主数字色解耦：标签字符串"热"/"真"必须保持各自属性色，不被 dominant/boost 衰减干扰
            // 旧协议路径：空字段，C# fallback 到 mainColor
            const efTextColorHex = e.isAggregator ? e.efTextColorId.toString(16).toUpperCase() : "";

            const segment = stgX + "," + stgY + "," +
                            combinedScale + "," + alpha + "," + combinedBlur + "," +
                            (e.displayDmg | 0) + "," + e.packed + "," +
                            e.efText + "," + e.efEmoji + "," +
                            e.lifeSteal + "," + e.shieldAbsorb + "," +
                            hits + "," + flagScales + "," + rgbHex + "," + efTextColorHex;

            // Aggregator 一律走 high 层（即便 hits=1 也是视觉锚点，必须 Z-top）
            if (e.isAggregator || hits > 1) {
                if (resultHigh.length > 0) resultHigh += ";";
                resultHigh += segment;
            } else {
                if (resultLow.length > 0) resultLow += ";";
                resultLow += segment;
            }

            const nf = advanceFrame(e, f);
            e.frame = nf;
            if (nf < TOTAL_FRAMES) {
                _active[writeIdx++] = e;
            } else if (e.isAggregator) {
                cleanupDeadAggregator(e);
            } else if (e.unitId !== "" && _unitMap[e.unitId] === e) {
                delete _unitMap[e.unitId];
            }
        }

        _activeCount = writeIdx;

        if (resultHigh.length === 0) return resultLow;
        if (resultLow.length === 0) return resultHigh;
        return resultLow + ";" + resultHigh;
    }

    export function reset(): void {
        _activeCount = 0;
        _aggregatorCount = 0;
        _unitMap = Object.create(null);
    }

    export function activeCount(): number {
        return _activeCount;
    }
}
