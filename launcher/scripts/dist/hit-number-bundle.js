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
    const COLOR_TABLE_RGB = [
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
        [0xFF, 0xE7, 0x70] // 10: 浅黄
    ];
    /** RGB 每帧向 target 移动比例（指数衰减）：0.15 ≈ 8 帧达成 ~75% 接近，自然柔和 */
    const COLOR_DECAY_RATIO = 0.15;
    const COLOR_TABLE_LENGTH = 11;
    function getColorRGB(cid) {
        return cid >= 0 && cid < COLOR_TABLE_LENGTH ? COLOR_TABLE_RGB[cid] : COLOR_TABLE_RGB[0];
    }
    function toHexByte(v) {
        let x = Math.round(v);
        if (x < 0)
            x = 0;
        else if (x > 255)
            x = 255;
        const s = x.toString(16);
        return s.length === 1 ? "0" + s : s;
    }
    let _aggregatorCount = 0;
    // 旧协议 entry 的占位数组：所有非 aggregator entry 共享，避免重复分配。
    // tick() 旧协议路径直接 hardcode flagScales="999999999" + rgbHex=""，不读这些字段；
    // 写入路径（pulseAggregator）仅由 isAggregator=true 的 entry 进入，sentinel 不会被污染。
    // Object.freeze 作为静态护栏：万一未来回归引入误写，会在 strict 模式下抛错而非静默污染。
    const PLACEHOLDER_FLAG_SUM = Object.freeze([0, 0, 0, 0, 0, 0, 0, 0, 0]);
    const PLACEHOLDER_FLAG_SCALES = Object.freeze([1, 1, 1, 1, 1, 1, 1, 1, 1]);
    const PLACEHOLDER_COLOR_SUM = Object.freeze([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    /** 找当前 _active 中距离 (rawX, rawY) 最近的 aggregator entry。aggregator 满员时使用 */
    function findNearestAggregator(rawX, rawY) {
        let best = null;
        let bestDist = Infinity;
        for (let i = 0; i < _activeCount; i++) {
            const e = _active[i];
            if (!e.isAggregator)
                continue;
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
    function pulseAggregator(e, parts, dmg, rawX, rawY) {
        const newPacked = +parts[3];
        // MISS 过滤：MISS 段不入 aggregator（既不累加伤害也不刷状态、不脉动）
        if ((newPacked & PACKED_MISS_MASK) !== 0)
            return;
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
        let highBits;
        if (dmg > e.maxSegmentDmg) {
            e.maxSegmentDmg = dmg;
            highBits = newPacked & ~PACKED_LOW10_MASK;
        }
        else {
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
        const et = HitNumber.unescField(parts[4]);
        const ee = HitNumber.unescField(parts[5]);
        if (et) {
            e.efText = et;
            // EF_DMG_TYPE_LABEL (bit 3) 触发时同步记录该段 colorId，渲染端据此决定标签颜色
            // EF_CRUSH_LABEL (bit 4) 颜色固定 #66BCF5，无需 efTextColorId
            if ((newPacked & 8) !== 0) {
                e.efTextColorId = (newPacked >> 18) & 15;
            }
        }
        if (ee)
            e.efEmoji = ee;
        const ls = +parts[6];
        const sa = +parts[7];
        if (ls > 0)
            e.lifeSteal += ls;
        if (sa > 0)
            e.shieldAbsorb += sa;
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
    function cleanupDeadAggregator(e) {
        for (const uid in _unitMap) {
            if (_unitMap[uid] === e)
                delete _unitMap[uid];
        }
        _aggregatorCount--;
    }
    const _active = [];
    let _activeCount = 0;
    // unitId → entry 引用映射。无原型对象避免 __proto__ / constructor 污染。
    // 存引用而非索引：tick 中 swap-remove 不动 map，唯一同步点是 entry 死亡时 delete。
    let _unitMap = Object.create(null);
    function findMergeTargetByDistance(rawX, rawY) {
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
    function mergeInto(existing, parts, dmg) {
        existing.targetDmg += dmg;
        existing.targetHits++;
        // displayHits 不变——tick 时逐帧递增
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
    function spawnBatch(raw) {
        if (!raw || raw.length === 0)
            return;
        const entries = raw.split(";");
        // 本批次内同 uid 临时锚点（避免同帧多段重复创建 aggregator）
        const sameFrameAggregators = Object.create(null);
        for (let i = 0; i < entries.length; i++) {
            const parts = entries[i].split("|");
            if (parts.length < 8)
                continue;
            const rawX = +parts[1];
            const rawY = +parts[2];
            const dmg = +parts[0];
            const uid = parts.length >= 9 ? parts[8] : "";
            // === 新协议路径：aggregator-only ===
            if (uid !== "") {
                let aggregator = _unitMap[uid];
                if (aggregator === undefined)
                    aggregator = sameFrameAggregators[uid];
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
                if ((firstPacked & PACKED_MISS_MASK) !== 0)
                    continue;
                if (_activeCount >= MAX_ACTIVE)
                    continue;
                // efFlagDmgSum + displayFlagScales 初始化：
                // - 首段触发的 flag：dmg 计入累计，displayFlagScale = 1.0（即时反馈）
                // - 未触发的 flag：累计 0，display 0
                const initFlagSums = [0, 0, 0, 0, 0, 0, 0, 0, 0];
                const initDisplayScales = [0, 0, 0, 0, 0, 0, 0, 0, 0];
                const initFlags = firstPacked & PACKED_EFFLAGS_MASK;
                for (let bit = 0; bit < 9; bit++) {
                    if ((initFlags & (1 << bit)) !== 0) {
                        initFlagSums[bit] = dmg;
                        initDisplayScales[bit] = 1.0;
                    }
                }
                // colorIdDmgSum + displayRGB 初始化
                const initColorSums = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
                const firstCid = (firstPacked >> 18) & 15;
                if (firstCid < COLOR_TABLE_LENGTH)
                    initColorSums[firstCid] = dmg;
                const firstRgb = getColorRGB(firstCid);
                const aggEntry = {
                    worldX: rawX, // aggregator 不含 ±60 偏移，钉在 unit 位置
                    worldY: rawY,
                    rawX: rawX,
                    rawY: rawY,
                    targetDmg: dmg,
                    displayDmg: dmg,
                    packed: firstPacked & ~PACKED_MISS_MASK, // 防御：清 isMISS（即便上面已过滤）
                    efText: HitNumber.unescField(parts[4]),
                    efEmoji: HitNumber.unescField(parts[5]),
                    lifeSteal: +parts[6],
                    shieldAbsorb: +parts[7],
                    frame: 0,
                    targetHits: 1,
                    displayHits: 1,
                    unitId: uid,
                    isAggregator: true,
                    silentFrames: 0,
                    pulseTimer: PULSE_DURATION, // 首次创建即给一次脉动反馈
                    maxSegmentDmg: dmg, // 初始最大段就是首段
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
            // 当前所有 caller（DamageResult.triggerDisplay → enqueueRaw）都传 hitTarget._name；
            // AS2 MovieClip 的 _name 永远非空，所以本分支事实上只在"ts bundle 已升级但 AS2 仍是旧版"
            // 这种过渡期被命中。保留是为了热替换 dist/hit-number-bundle.js 时不破坏显示。
            const highDensity = _activeCount > DENSITY_LOW;
            if (highDensity) {
                const mi = findMergeTargetByDistance(rawX, rawY);
                if (mi >= 0) {
                    mergeInto(_active[mi], parts, dmg);
                    continue;
                }
            }
            if (_activeCount >= MAX_ACTIVE)
                continue;
            const entry = {
                worldX: rawX + (Math.random() - 0.5) * POSITION_OFFSET * 2,
                worldY: rawY + (Math.random() - 0.5) * POSITION_OFFSET * 2,
                rawX: rawX,
                rawY: rawY,
                targetDmg: dmg,
                displayDmg: dmg,
                packed: +parts[3],
                efText: HitNumber.unescField(parts[4]),
                efEmoji: HitNumber.unescField(parts[5]),
                lifeSteal: +parts[6],
                shieldAbsorb: +parts[7],
                frame: 0,
                targetHits: 1,
                displayHits: 1,
                unitId: "",
                isAggregator: false,
                silentFrames: 0,
                pulseTimer: 0, // 旧协议 entry 不脉动
                maxSegmentDmg: 0, // 不使用
                efFlagDmgSum: PLACEHOLDER_FLAG_SUM, // 共享 sentinel（frozen），旧协议不读不写
                displayFlagScales: PLACEHOLDER_FLAG_SCALES, // 共享 sentinel（frozen），tick 旧协议路径硬编码 "999999999"
                colorIdDmgSum: PLACEHOLDER_COLOR_SUM, // 共享 sentinel（frozen），仅 aggregator 用
                displayR: 0, displayG: 0, displayB: 0, // 占位，旧协议输出空 hex 字段，C# fallback 用 colorId
                efTextColorId: 0 // 占位（旧协议不输出 fields[14]，C# fallback 用 mainColor）
            };
            _active[_activeCount++] = entry;
        }
        // 批次结束：本帧创建的 aggregator 注册到 _unitMap
        for (const uid in sameFrameAggregators) {
            _unitMap[uid] = sameFrameAggregators[uid];
        }
    }
    HitNumber.spawnBatch = spawnBatch;
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
    function advanceFrame(e, f) {
        if (e.isAggregator) {
            e.silentFrames++;
            if (f < AGGREGATOR_HOLD_FRAME)
                return f + 1;
            if (e.silentFrames >= AGGREGATOR_QUIET_FRAMES)
                return f + 1;
            return f; // 稳态停留
        }
        return f + 1;
    }
    /**
     * 每帧调用。输出 stride=15：
     *   stgX, stgY, combinedScale, alpha, combinedBlur,
     *   damage, packed, efText, efEmoji,
     *   lifeSteal, shieldAbsorb, displayHits,
     *   flagScales, rgbHex, efTextColorHex
     *
     * 视觉层级：
     *   - Aggregator / 距离合并的 hits>1 → resultHigh → 最上层
     *   - 旧协议独立 entry → resultLow → 垫底
     *   - 字号统一 baseScale × 1.0（不放大，避免怪海堆积）；旧协议距离合并按 hits 微放大保留原行为
     */
    function tick() {
        if (_activeCount === 0)
            return "";
        const cam = HitNumber.camera;
        let resultLow = "";
        let resultHigh = "";
        let writeIdx = 0;
        for (let i = 0; i < _activeCount; i++) {
            const e = _active[i];
            const f = e.frame;
            if (f >= TOTAL_FRAMES) {
                if (e.isAggregator) {
                    cleanupDeadAggregator(e);
                }
                else if (e.unitId !== "" && _unitMap[e.unitId] === e) {
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
            const textX = e.worldX + HitNumber.offsetXLUT[f];
            const textY = e.worldY + HitNumber.offsetYLUT[f];
            const stgX = cam.gx + textX * cam.sx;
            const stgY = cam.gy + textY * cam.sx;
            if (stgX < -MARGIN || stgX > HitNumber.STAGE_W + MARGIN ||
                stgY < -MARGIN || stgY > HitNumber.STAGE_H + MARGIN) {
                const nf = advanceFrame(e, f);
                e.frame = nf;
                if (nf < TOTAL_FRAMES) {
                    _active[writeIdx++] = e;
                }
                else if (e.isAggregator) {
                    cleanupDeadAggregator(e);
                }
                else if (e.unitId !== "" && _unitMap[e.unitId] === e) {
                    delete _unitMap[e.unitId];
                }
                continue;
            }
            const baseScale = HitNumber.scaleLUT[f] * cam.sx;
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
            const alpha = HitNumber.getAlpha(f);
            const combinedBlur = HitNumber.blurLUT[f] * cam.sx;
            // Aggregator: efFlag displayScale 演化 + RGB 颜色插值
            //   efFlag: target = ratio 映射（FLOOR..CEIL 线性），display 向 target 线性追赶
            //   RGB:    target = dominant colorId（colorIdDmgSum 最高者）对应 RGB
            //           display 向 target 指数衰减（COLOR_DECAY_RATIO），暴击段瞬时 boost 已在 pulseAggregator 处理
            //   旧协议路径：flag scale 固定 9，rgbHex 空字符串（C# fallback 用 colorId）
            let flagScales;
            let rgbHex;
            if (e.isAggregator && e.targetDmg > 0) {
                const totalDmg = e.targetDmg;
                let s = "";
                for (let bit = 0; bit < 9; bit++) {
                    let target;
                    if (bit === EF_EXECUTE_BIT) {
                        // EXECUTE 豁免：只要曾触发过（efFlagDmgSum>0）就保持 target=1.0
                        target = e.efFlagDmgSum[bit] > 0 ? 1.0 : 0;
                    }
                    else {
                        const ratio = e.efFlagDmgSum[bit] / totalDmg;
                        if (ratio < VISIBILITY_FLOOR)
                            target = 0;
                        else if (ratio >= VISIBILITY_CEIL)
                            target = 1.0;
                        else
                            target = (ratio - VISIBILITY_FLOOR) / (VISIBILITY_CEIL - VISIBILITY_FLOOR);
                    }
                    // approach: display 向 target 线性追赶
                    const cur = e.displayFlagScales[bit];
                    let next;
                    if (cur < target)
                        next = cur + DECAY_STEP > target ? target : cur + DECAY_STEP;
                    else if (cur > target)
                        next = cur - DECAY_STEP < target ? target : cur - DECAY_STEP;
                    else
                        next = cur;
                    e.displayFlagScales[bit] = next;
                    // 编码 0-9 level：next * 9 四舍五入；< 0.02 直接为 0（接近消失即不渲染）。
                    // 阈值贴近 0 是为了配合 C# 端 level/9 线性公式（level=1 → 0.111×，最小可见态被
                    // 各标签的 Math.Max(4f, ...) clamp 兜到 ≈ 4pt）：让"显示→消失"过渡只跨越一帧
                    // （DECAY_STEP=0.05），观感上没有明显 pop。
                    let level;
                    if (next < 0.02)
                        level = 0;
                    else
                        level = Math.round(next * 9);
                    if (level > 9)
                        level = 9;
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
            }
            else {
                flagScales = "999999999"; // 旧协议：所有 flag 满字号
                rgbHex = ""; // 旧协议：空字段，C# fallback 用 colorId
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
                if (resultHigh.length > 0)
                    resultHigh += ";";
                resultHigh += segment;
            }
            else {
                if (resultLow.length > 0)
                    resultLow += ";";
                resultLow += segment;
            }
            const nf = advanceFrame(e, f);
            e.frame = nf;
            if (nf < TOTAL_FRAMES) {
                _active[writeIdx++] = e;
            }
            else if (e.isAggregator) {
                cleanupDeadAggregator(e);
            }
            else if (e.unitId !== "" && _unitMap[e.unitId] === e) {
                delete _unitMap[e.unitId];
            }
        }
        _activeCount = writeIdx;
        if (resultHigh.length === 0)
            return resultLow;
        if (resultLow.length === 0)
            return resultHigh;
        return resultLow + ";" + resultHigh;
    }
    HitNumber.tick = tick;
    function reset() {
        _activeCount = 0;
        _aggregatorCount = 0;
        _unitMap = Object.create(null);
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
/**
 * CommandDFA - 搓招 DFA 状态机 (镜像 AS2 CommandDFA.as 的 updateFast)
 *
 * V8 侧职责：DFA 状态转移 + 输入路径追踪。不做缓冲。
 * 超时语义与 AS2 原版一致：每帧 timer++，超过 timeout 回 ROOT。
 */
var GameInput;
(function (GameInput) {
    const ROOT_STATE = 0;
    const NO_COMMAND = 0;
    const DEFAULT_TIMEOUT = 8;
    class CommandDfa {
        constructor() {
            this._dfa = null;
            this._state = ROOT_STATE;
            this._timer = 0;
            this._commandId = NO_COMMAND;
            this._lastCommandId = NO_COMMAND;
            this._inputPath = [];
        }
        setDfa(dfa) {
            this._dfa = dfa;
            this.resetState();
        }
        resetState() {
            this._state = ROOT_STATE;
            this._timer = 0;
            this._commandId = NO_COMMAND;
            this._lastCommandId = NO_COMMAND;
            this._inputPath.length = 0;
        }
        getCommandId() { return this._commandId; }
        getLastCommandId() { return this._lastCommandId; }
        getState() { return this._state; }
        getInputPath() { return this._inputPath; }
        /**
         * 热路径：内联 DFA 状态转移 + 路径追踪
         * 与 AS2 原版语义一致：每帧 timer++，有效转移时 timer=0，超时回 ROOT。
         */
        updateFast(events, timeout = DEFAULT_TIMEOUT) {
            const dfa = this._dfa;
            if (dfa === null || !dfa.isLoaded()) {
                this._commandId = NO_COMMAND;
                return;
            }
            let state = this._state;
            let timer = this._timer;
            const path = this._inputPath;
            this._commandId = NO_COMMAND;
            timer++;
            const evCount = events.length;
            for (let i = 0; i < evCount; i++) {
                const ev = events[i];
                const nextState = dfa.transition(state, ev);
                if (nextState >= 0) {
                    state = nextState;
                    timer = 0;
                    path.push(ev);
                    const cmd = dfa.getAccept(state);
                    if (cmd > 0) {
                        this._commandId = cmd;
                        this._lastCommandId = cmd;
                    }
                }
            }
            if (timer > timeout) {
                state = ROOT_STATE;
                timer = 0;
                path.length = 0;
            }
            this._state = state;
            this._timer = timer;
        }
    }
    GameInput.CommandDfa = CommandDfa;
})(GameInput || (GameInput = {}));
/**
 * InputEvent - 输入事件常量 (镜像 AS2 InputEvent.as)
 *
 * 搓招系统使用的 18 种输入事件。方向归一化：前/后/上/下，不区分左右。
 */
var GameInput;
(function (GameInput) {
    // 无事件
    GameInput.EV_NONE = 0;
    // 方向事件（归一化：前=面向方向，后=背向方向）
    GameInput.EV_FORWARD = 1;
    GameInput.EV_BACK = 2;
    GameInput.EV_DOWN = 3;
    GameInput.EV_UP = 4;
    GameInput.EV_DOWN_FORWARD = 5;
    GameInput.EV_DOWN_BACK = 6;
    GameInput.EV_UP_FORWARD = 7;
    GameInput.EV_UP_BACK = 8;
    // 按键边沿事件（按下瞬间触发）
    GameInput.EV_A_PRESS = 9;
    GameInput.EV_B_PRESS = 10;
    GameInput.EV_C_PRESS = 11;
    // 复合事件
    GameInput.EV_DOUBLE_TAP_FORWARD = 12;
    GameInput.EV_DOUBLE_TAP_BACK = 13;
    GameInput.EV_SHIFT_HOLD = 14;
    GameInput.EV_SHIFT_FORWARD = 15;
    GameInput.EV_SHIFT_BACK = 16;
    GameInput.EV_SHIFT_DOWN = 17;
    // 字母表大小（DFA 数组分配用）
    GameInput.ALPHABET_SIZE = 18;
    // 事件名称（调试 + 可视化提示）
    const _names = [
        "NONE",
        "→", // FORWARD
        "←", // BACK
        "↓", // DOWN
        "↑", // UP
        "↘", // DOWN_FORWARD
        "↙", // DOWN_BACK
        "↗", // UP_FORWARD
        "↖", // UP_BACK
        "A", // A_PRESS
        "B", // B_PRESS
        "C", // C_PRESS
        "→→", // DOUBLE_TAP_FORWARD
        "←←", // DOUBLE_TAP_BACK
        "Shift", // SHIFT_HOLD
        "Shift+→", // SHIFT_FORWARD
        "Shift+←", // SHIFT_BACK
        "Shift+↓" // SHIFT_DOWN
    ];
    function eventName(id) {
        return (id >= 0 && id < _names.length) ? _names[id] : "?";
    }
    GameInput.eventName = eventName;
    function sequenceToString(events) {
        let s = "";
        for (let i = 0; i < events.length; i++) {
            s += eventName(events[i]);
        }
        return s;
    }
    GameInput.sequenceToString = sequenceToString;
})(GameInput || (GameInput = {}));
/**
 * InputProcessor - 顶层编排 (GameInput namespace 入口)
 *
 * K payload 格式 v2:
 *   chr(cmdId+0x20) \x01 {typed} \x02 {hints}
 *
 *   - cmdId=0: 无命中, typed=已输入序列符号, hints=可达分支
 *   - cmdId>0: 命中, typed=完整触发序列, hints="" (命中时无分支)
 *
 *   typed: "↓↘" (已输入的事件符号序列)
 *   hints: "波动拳:↓↘A:1;诛杀步:→→:2" (name:fullSequence:remainSteps)
 *          fullSequence 包含 typed 部分 + 剩余部分
 */
var GameInput;
(function (GameInput) {
    const _modules = {};
    let _sampler = null;
    let _currentModuleId = -1;
    let _lastHintState = -1;
    let _lastHintStr = "";
    // 显示层防闪烁：hints 非空时缓存，回 ROOT 时延持几帧再清空
    let _displayHints = "";
    let _displayTyped = "";
    let _displayHoldTimer = 0;
    const DISPLAY_HOLD_FRAMES = 10; // hints 消失后保持 10 帧（~333ms）
    // 日志
    let _logBuf = [];
    function _log(msg) {
        _logBuf.push(msg);
    }
    function flushLog() {
        if (_logBuf.length === 0)
            return "";
        const result = _logBuf.join("\n");
        _logBuf = [];
        return result;
    }
    GameInput.flushLog = flushLog;
    function init() {
        _sampler = new GameInput.InputSampler();
        _currentModuleId = -1;
        _log("[GameInput] init OK");
    }
    GameInput.init = init;
    function loadModule(moduleId, dataJson) {
        const id = parseInt(moduleId, 10);
        if (isNaN(id)) {
            _log("[GameInput] loadModule: invalid moduleId: " + moduleId);
            return;
        }
        _log("[GameInput] loadModule: id=" + id + " jsonLen=" + dataJson.length);
        let data;
        try {
            data = JSON.parse(dataJson);
        }
        catch (e) {
            _log("[GameInput] loadModule: JSON parse error: " + e);
            return;
        }
        const trans = data.transitions;
        for (let i = 0; i < trans.length; i++) {
            if (trans[i] === null || trans[i] === undefined) {
                trans[i] = -1;
            }
        }
        const dfa = new GameInput.TrieDfa();
        dfa.load(data);
        const cmdDfa = new GameInput.CommandDfa();
        cmdDfa.setDfa(dfa);
        _modules[id] = { dfa, cmdDfa };
        _log("[GameInput] loadModule OK: id=" + id +
            " alpha=" + data.alphabetSize +
            " states=" + (data.accept ? data.accept.length : 0) +
            " names=" + (data.commandNames ? data.commandNames.length : 0));
    }
    GameInput.loadModule = loadModule;
    /**
     * 构建 hints 字符串：每个可达搓招的 name:fullSequence:remainSteps
     * fullSequence = typed 部分 + remaining 部分（完整路径，供 UI 渲染进度）
     */
    function buildHints(mod, state, typedStr) {
        if (state === 0)
            return "";
        const reachable = mod.dfa.getReachable(state);
        if (reachable.length === 0)
            return "";
        let buf = "";
        let count = 0;
        for (let i = 0; i < reachable.length; i++) {
            const h = reachable[i];
            // 完整序列 = 已输入 + 剩余
            const fullSeq = typedStr + h.remaining;
            if (count > 0)
                buf += ";";
            buf += h.name + ":" + fullSeq + ":" + h.steps;
            count++;
        }
        return buf;
    }
    function processFrame(mask, facingBit, moduleId, doubleTapDir) {
        if (_sampler === null)
            return String.fromCharCode(0x20);
        const mod = _modules[moduleId];
        if (!mod)
            return String.fromCharCode(0x20);
        // 模组切换时重置 DFA + 显示缓存
        if (moduleId !== _currentModuleId) {
            mod.cmdDfa.resetState();
            _currentModuleId = moduleId;
            _lastHintState = -1;
            _lastHintStr = "";
            _displayHints = "";
            _displayTyped = "";
            _displayHoldTimer = 0;
        }
        // 1. InputSampler → events
        const facingRight = facingBit !== 0;
        const events = _sampler.sample(mask, facingRight, doubleTapDir);
        // 2. CommandDFA → cmdId (timeout 已内置 8 帧)
        mod.cmdDfa.updateFast(events);
        const cmdId = mod.cmdDfa.getCommandId();
        const state = mod.cmdDfa.getState();
        const inputPath = mod.cmdDfa.getInputPath();
        // typed: 已输入事件的符号序列
        const typedStr = GameInput.sequenceToString(inputPath);
        // 3. hints: 仅 state 变化时重算
        let rawHints;
        if (state !== _lastHintState) {
            _lastHintState = state;
            _lastHintStr = buildHints(mod, state, typedStr);
        }
        rawHints = _lastHintStr;
        // 4. 显示层防闪烁
        //    DFA 在"持续按住 → 超时回 ROOT → 再转移"时会导致 hints 在有/无之间振荡。
        //    解决：hints 非空时更新显示缓存；hints 变空后延持 DISPLAY_HOLD_FRAMES 帧再清。
        let outTyped;
        let outHints;
        if (rawHints.length > 0) {
            // 有新 hints → 更新显示缓存
            _displayHints = rawHints;
            _displayTyped = typedStr;
            _displayHoldTimer = DISPLAY_HOLD_FRAMES;
            outTyped = typedStr;
            outHints = rawHints;
        }
        else if (_displayHoldTimer > 0) {
            // hints 变空但延持中 → 继续输出缓存
            _displayHoldTimer--;
            outTyped = _displayTyped;
            outHints = _displayHints;
        }
        else {
            // 延持结束 → 真正清空
            _displayHints = "";
            _displayTyped = "";
            outTyped = "";
            outHints = "";
        }
        // 5. 格式化 K payload: chr(cmdId+0x20) \x01 typed \x02 hints
        if (cmdId === 0) {
            return String.fromCharCode(0x20) + "\x01" + outTyped + "\x02" + outHints;
        }
        // 命中
        const cmdName = mod.dfa.getCommandName(cmdId);
        // HIT 日志已由 WebView2 combo overlay 接管，不再写文件日志
        // 命中时清空显示缓存（由 AS2 N 前缀接管显示）
        _displayHoldTimer = 0;
        _displayHints = "";
        _displayTyped = "";
        return String.fromCharCode(cmdId + 0x20) + cmdName + "\x01" + typedStr + "\x02";
    }
    GameInput.processFrame = processFrame;
})(GameInput || (GameInput = {}));
/**
 * InputSampler - 输入采样器 (镜像 AS2 InputSampler.as)
 *
 * 职责：将 8-bit bitmask + 朝向 + doubleTapDir 转换为 InputEvent[] 列表。
 * 帧制语义：双击检测用帧计数器 + 帧间隔窗口（与 AS2 一致，不用 ms）。
 *
 * Bitmask bit 分配:
 *   0=左 1=右 2=上 3=下 4=A 5=B 6=C 7=Shift
 */
var GameInput;
(function (GameInput) {
    // Bitmask bit constants
    const BIT_LEFT = 1;
    const BIT_RIGHT = 2;
    const BIT_UP = 4;
    const BIT_DOWN = 8;
    const BIT_A = 16;
    const BIT_B = 32;
    const BIT_C = 64;
    const BIT_SHIFT = 128;
    class InputSampler {
        constructor() {
            // 上一帧状态（边沿检测）
            this._prevMask = 0;
            this._prevDoubleTapDir = 0;
            // 帧级双击检测状态
            this._frameCounter = 0;
            this._lastForwardFrame = -100;
            this._lastBackFrame = -100;
            this._doubleTapWindow = 12; // ~400ms @30fps
            // 上一帧归一化方向（用于帧级双击边沿）
            this._prevHoldForward = false;
            this._prevHoldBack = false;
            // 事件缓冲（复用）
            this._buf = [];
        }
        reset() {
            this._prevMask = 0;
            this._prevDoubleTapDir = 0;
            this._frameCounter = 0;
            this._lastForwardFrame = -100;
            this._lastBackFrame = -100;
            this._prevHoldForward = false;
            this._prevHoldBack = false;
        }
        /**
         * 采样本帧输入，返回事件列表
         *
         * @param mask 当前帧 8-bit bitmask（AS2 Key.isDown() 生成）
         * @param facingRight 角色面向右=true
         * @param doubleTapDir -1/0/1（KeyManager 写入的双击方向）
         * @returns InputEvent ID 数组
         */
        sample(mask, facingRight, doubleTapDir) {
            this._frameCounter++;
            const buf = this._buf;
            buf.length = 0;
            const prevMask = this._prevMask;
            // 解码 bitmask
            const left = (mask & BIT_LEFT) !== 0;
            const right = (mask & BIT_RIGHT) !== 0;
            const up = (mask & BIT_UP) !== 0;
            const down = (mask & BIT_DOWN) !== 0;
            const keyA = (mask & BIT_A) !== 0;
            const keyB = (mask & BIT_B) !== 0;
            const keyC = (mask & BIT_C) !== 0;
            const shift = (mask & BIT_SHIFT) !== 0;
            const prevA = (prevMask & BIT_A) !== 0;
            const prevB = (prevMask & BIT_B) !== 0;
            const prevC = (prevMask & BIT_C) !== 0;
            // 方向归一化
            const holdForward = facingRight ? right : left;
            const holdBack = facingRight ? left : right;
            // === 方向事件（复合优先）===
            if (down && holdForward) {
                buf.push(GameInput.EV_DOWN_FORWARD);
            }
            else if (down && holdBack) {
                buf.push(GameInput.EV_DOWN_BACK);
            }
            else if (up && holdForward) {
                buf.push(GameInput.EV_UP_FORWARD);
            }
            else if (up && holdBack) {
                buf.push(GameInput.EV_UP_BACK);
            }
            else {
                if (down)
                    buf.push(GameInput.EV_DOWN);
                if (up)
                    buf.push(GameInput.EV_UP);
                if (holdForward)
                    buf.push(GameInput.EV_FORWARD);
                if (holdBack)
                    buf.push(GameInput.EV_BACK);
            }
            // === 按键边沿检测（按下瞬间）===
            if (keyA && !prevA)
                buf.push(GameInput.EV_A_PRESS);
            if (keyB && !prevB)
                buf.push(GameInput.EV_B_PRESS);
            if (keyC && !prevC)
                buf.push(GameInput.EV_C_PRESS);
            // === Shift 组合事件 ===
            if (shift) {
                buf.push(GameInput.EV_SHIFT_HOLD);
                if (holdForward)
                    buf.push(GameInput.EV_SHIFT_FORWARD);
                if (holdBack)
                    buf.push(GameInput.EV_SHIFT_BACK);
                if (down)
                    buf.push(GameInput.EV_SHIFT_DOWN);
            }
            // === 双击检测通道1: doubleTapDir 边沿（KeyManager 毫秒级）===
            const prevDir = this._prevDoubleTapDir;
            if (doubleTapDir !== 0 && prevDir === 0) {
                if (facingRight) {
                    buf.push(doubleTapDir > 0 ? GameInput.EV_DOUBLE_TAP_FORWARD : GameInput.EV_DOUBLE_TAP_BACK);
                }
                else {
                    buf.push(doubleTapDir < 0 ? GameInput.EV_DOUBLE_TAP_FORWARD : GameInput.EV_DOUBLE_TAP_BACK);
                }
            }
            // === 双击检测通道2: 帧级 fallback（镜像 InputSampler.as:256-283）===
            const frame = this._frameCounter;
            // 前方向
            if (holdForward && !this._prevHoldForward) {
                if (frame - this._lastForwardFrame <= this._doubleTapWindow) {
                    buf.push(GameInput.EV_DOUBLE_TAP_FORWARD);
                    this._lastForwardFrame = -100;
                }
            }
            if (!holdForward && this._prevHoldForward) {
                this._lastForwardFrame = frame;
            }
            // 后方向
            if (holdBack && !this._prevHoldBack) {
                if (frame - this._lastBackFrame <= this._doubleTapWindow) {
                    buf.push(GameInput.EV_DOUBLE_TAP_BACK);
                    this._lastBackFrame = -100;
                }
            }
            if (!holdBack && this._prevHoldBack) {
                this._lastBackFrame = frame;
            }
            // === 更新 prev 状态 ===
            this._prevMask = mask;
            this._prevDoubleTapDir = doubleTapDir;
            this._prevHoldForward = holdForward;
            this._prevHoldBack = holdBack;
            return buf;
        }
    }
    GameInput.InputSampler = InputSampler;
})(GameInput || (GameInput = {}));
/**
 * TrieDFA - 扁平数组前缀树 DFA (镜像 AS2 TrieDFA.as 运行时部分)
 *
 * 不实现 insert/compile（由 AS2 编译后序列化传入），
 * 只实现运行时查询：transition, getAccept, getReachable(BFS)。
 */
var GameInput;
(function (GameInput) {
    class TrieDfa {
        constructor() {
            this._alpha = 0;
            this._trans = [];
            this._accept = [];
            this._depth = [];
            this._hint = [];
            this._patterns = [];
            this._names = [];
            this._stateCount = 0;
            this._loaded = false;
        }
        load(data) {
            this._alpha = data.alphabetSize;
            this._trans = data.transitions;
            this._accept = data.accept;
            this._depth = data.depth;
            this._hint = data.hint;
            this._patterns = data.patterns;
            this._names = data.commandNames;
            this._stateCount = this._accept.length;
            this._loaded = true;
        }
        isLoaded() {
            return this._loaded;
        }
        /**
         * O(1) 状态转移
         * @returns nextState, or -1 if no transition
         */
        transition(state, symbol) {
            const next = this._trans[state * this._alpha + symbol];
            return (next !== undefined && next >= 0) ? next : -1;
        }
        /**
         * 获取 accepting state 的 patternId (0 = non-accepting)
         */
        getAccept(state) {
            const a = this._accept[state];
            return (a !== undefined && a > 0) ? a : 0;
        }
        getDepth(state) {
            return this._depth[state] || 0;
        }
        getHint(state) {
            return this._hint[state] || 0;
        }
        getCommandName(patternId) {
            return this._names[patternId] || "";
        }
        getPattern(patternId) {
            return this._patterns[patternId] || null;
        }
        getAlphabetSize() {
            return this._alpha;
        }
        /**
         * BFS 从 currentState 出发，找所有可达的 accepting states
         * 返回搓招提示列表（Phase 4 可视化用）
         */
        getReachable(currentState) {
            if (!this._loaded || currentState < 0)
                return [];
            const alpha = this._alpha;
            const trans = this._trans;
            const accept = this._accept;
            const names = this._names;
            const patterns = this._patterns;
            // BFS: [state, path from currentState]
            const queue = [];
            const visited = new Set();
            const hints = [];
            visited.add(currentState);
            // Seed: all transitions from currentState
            for (let sym = 0; sym < alpha; sym++) {
                const next = trans[currentState * alpha + sym];
                if (next !== undefined && next >= 0 && !visited.has(next)) {
                    visited.add(next);
                    queue.push({ state: next, path: [sym] });
                }
            }
            let head = 0;
            while (head < queue.length) {
                const item = queue[head++];
                const st = item.state;
                const path = item.path;
                // Check if accepting
                const pid = accept[st];
                if (pid !== undefined && pid > 0) {
                    const name = names[pid] || "";
                    if (name.length > 0) {
                        hints.push({
                            name: name,
                            remaining: GameInput.sequenceToString(path),
                            steps: path.length
                        });
                    }
                }
                // Expand neighbors (limit depth to avoid explosion)
                if (path.length < 8) {
                    for (let sym = 0; sym < alpha; sym++) {
                        const next = trans[st * alpha + sym];
                        if (next !== undefined && next >= 0 && !visited.has(next)) {
                            visited.add(next);
                            const newPath = path.slice();
                            newPath.push(sym);
                            queue.push({ state: next, path: newPath });
                        }
                    }
                }
            }
            return hints;
        }
    }
    GameInput.TrieDfa = TrieDfa;
})(GameInput || (GameInput = {}));
