(function(root, factory) {
    "use strict";

    var commonJs = !!(typeof module === "object" && module.exports);

    function secureRandomBytes(length) {
        var bytes;
        var index;
        if (root.crypto && typeof root.crypto.getRandomValues === "function") {
            bytes = new Uint8Array(length);
            root.crypto.getRandomValues(bytes);
            return bytes;
        }
        if (commonJs) {
            var nodeBytes = require("crypto").randomBytes(length);
            bytes = new Uint8Array(length);
            for (index = 0; index < length; index += 1) bytes[index] = nodeBytes[index];
            return bytes;
        }
        throw new Error("secure session entropy unavailable");
    }

    var api = factory({ randomBytes: secureRandomBytes, commonJs: commonJs });
    if (commonJs) module.exports = api;
    else root.BlackMarketCore = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function(environment) {
    "use strict";

    var SNAPSHOT_SCHEMA = "black-market-anonymous-shadow.v2";
    var ALGORITHM_VERSION = "object-sdf-nanobot-sludge.v3";
    // 购买前统一去色；素材来源只决定轮廓提取，成交揭晓才恢复原色。
    var HIDDEN_COLOR_MODE = "monochrome";
    var IDENTITY_BOUNDARY = "anonymous-synthetic-no-catalog.v2";
    var FIXTURE_DIGEST = "anonymous-shadow-fixture-v2";
    var LEVELS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    var COVERAGE_BY_LEVEL = {
        0: 0.97,
        1: 0.92,
        2: 0.88,
        3: 0.84,
        4: 0.69,
        5: 0.54,
        6: 0.46,
        7: 0.39,
        8: 0.32,
        9: 0.25,
        10: 0.18
    };
    var PRICE_POINTS = [5000, 7500, 10000, 15000, 20000, 30000];
    var RAW_BOX_REDEEM_TP = 5000;
    var TP_PER_K = 50;
    var MAX_RECEIPTS = 64;
    // 匿名视觉池：visual/visual-pool-manifest.js（tools/bake-black-market-visual-pool.js
    // 生成，--check 可复验）提供全目录渲染资格清单；清单缺失时回退固定安全 SVG。
    var SAFE_SURFACE_DATA_URL = "data:image/svg+xml;charset=utf-8," + encodeURIComponent([
        '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="192" viewBox="0 0 128 192">',
        '<path fill="#87908b" d="M25 35h78l13 25-9 98-43 22-43-22-9-98z"/>',
        '<path fill="#59635f" d="M25 35l39 20 39-20 13 25-52 25-52-25z"/>',
        '<path fill="#a7afa9" d="M58 55h12v113H58z"/>',
        '<path fill="#343b39" d="M32 94h64v12H32z"/>',
        '</svg>'
    ].join(""));

    function invariant(condition, message) {
        if (!condition) throw new Error(message);
    }

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function isObject(value) {
        return !!value && typeof value === "object" && !Array.isArray(value);
    }

    function isSafeNonNegativeInteger(value) {
        return Number.isSafeInteger(value) && value >= 0;
    }

    function isSafePositiveInteger(value) {
        return Number.isSafeInteger(value) && value > 0;
    }

    function isSafeString(value, max) {
        return typeof value === "string" && value.length > 0 && value.length <= max;
    }

    function hash32(text) {
        var hash = 2166136261 >>> 0;
        var source = String(text || "");
        var index;
        for (index = 0; index < source.length; index += 1) {
            hash ^= source.charCodeAt(index);
            hash = Math.imul(hash, 16777619) >>> 0;
        }
        return hash >>> 0;
    }

    function shuffleInPlace(list, rng) {
        for (var cursor = list.length - 1; cursor > 0; cursor -= 1) {
            var target = rng.int(cursor + 1);
            var tmp = list[cursor];
            list[cursor] = list[target];
            list[target] = tmp;
        }
    }

    // 计算同舱合法标价区间（满足高值回售净赚 >= 50 TP、低值回售必亏，且标价为 50 整数倍）。
    function computePriceBounds(lowSale, highSale) {
        if (!Number.isFinite(lowSale) || !Number.isFinite(highSale) || highSale <= lowSale) return null;
        var lower = Math.ceil((lowSale + 1) / TP_PER_K) * TP_PER_K;
        var upper = Math.floor((highSale - TP_PER_K) / TP_PER_K) * TP_PER_K;
        if (lower <= 0 || lower > upper) return null;
        return { lower: lower, upper: upper };
    }

    // 标价略微偏向上半区（52%–72%），使盲猜期望 <= 0：
    // 闭眼乱选没有白嫖正收益，看懂轮廓与升级解密才稳赚，整舱放过因此具备真实止损价值。
    function pickCounterPriceFromBounds(bounds, rng) {
        var slots = Math.floor((bounds.upper - bounds.lower) / TP_PER_K) + 1;
        if (slots <= 1) return bounds.lower;
        var biasMin = Math.floor((slots - 1) * 0.52);
        var biasMax = Math.min(slots - 1, Math.max(biasMin, Math.ceil((slots - 1) * 0.74)));
        var offset = biasMin + rng.int(biasMax - biasMin + 1);
        return bounds.lower + offset * TP_PER_K;
    }

    // 同组配对分配（对齐世界观“纳米群品种近似”与真值估值闭环）：
    // 1. 排除一图多物（同 u 共享不同价格）导致的不可辨识陷阱；
    // 2. 同一货舱左右两件来自同一分组（g 键）、视觉资产（u）互异、同页六件零撞车；
    // 3. 优先配对具有合法价差区间（high.s - low.s 可派生 50 倍数标价）的真实对子，
    //    让看清物品轮廓真正决定赚赔。
    function planVisualPairings(rng, entries) {
        if (!entries.length) return [];
        var uriCounts = {};
        var lastIndexByUri = {};
        var index;
        for (index = 0; index < entries.length; index += 1) {
            var uri = entries[index].u;
            uriCounts[uri] = (uriCounts[uri] || 0) + 1;
            lastIndexByUri[uri] = index;
        }
        var groups = {};
        var groupOrder = [];
        var fallbackGroups = {};
        var seenUnique = {};
        for (index = 0; index < entries.length; index += 1) {
            var entry = entries[index];
            var u = entry.u;
            // bm24 按 u 唯一反查最后一条记录，配对只采样该规范索引，彻底杜绝同图多义冲突。
            if (lastIndexByUri[u] !== index || seenUnique[u]) continue;
            seenUnique[u] = true;
            var key = String(entry.g || "?");
            if (!fallbackGroups[key]) fallbackGroups[key] = [];
            fallbackGroups[key].push(index);
            if (uriCounts[u] !== 1 || entry.e === "banned") continue;
            if (!groups[key]) {
                groups[key] = [];
                groupOrder.push(key);
            }
            groups[key].push(index);
        }
        shuffleInPlace(groupOrder, rng);

        var usedUris = {};
        var pairs = [];

        function tryPickPairFrom(members, requirePriced) {
            if (!members || members.length < 2) return null;
            var available = members.filter(function(idx) { return !usedUris[entries[idx].u]; });
            if (available.length < 2) return null;
            shuffleInPlace(available, rng);
            var maxChecks = Math.min(available.length, 24);
            for (var a = 0; a < maxChecks; a += 1) {
                var idxA = available[a];
                var itemA = entries[idxA];
                for (var b = a + 1; b < maxChecks; b += 1) {
                    var idxB = available[b];
                    var itemB = entries[idxB];
                    if (itemA.u === itemB.u) continue;
                    if (!requirePriced) {
                        usedUris[itemA.u] = true;
                        usedUris[itemB.u] = true;
                        return { first: idxA, second: idxB, bounds: null };
                    }
                    var lowSale = Math.min(Number(itemA.s) || 0, Number(itemB.s) || 0);
                    var highSale = Math.max(Number(itemA.s) || 0, Number(itemB.s) || 0);
                    // 避免单件天价超出常规影子余额区间
                    if (lowSale <= 0 || highSale > 200000) continue;
                    var bounds = computePriceBounds(lowSale, highSale);
                    if (!bounds || bounds.lower > 160000) continue;
                    usedUris[itemA.u] = true;
                    usedUris[itemB.u] = true;
                    return { first: idxA, second: idxB, bounds: bounds };
                }
            }
            return null;
        }

        // 第一轮：优先不同分组、有真实合法价差的对子
        for (var groupCursor = 0; groupCursor < groupOrder.length && pairs.length < 3; groupCursor += 1) {
            var picked = tryPickPairFrom(groups[groupOrder[groupCursor]], true);
            if (picked) pairs.push(picked);
        }
        // 第二轮：允许同分组重复抽第二对（如测试池被过滤成单一分组时）
        for (var retry = 0; retry < groupOrder.length && pairs.length < 3; retry += 1) {
            var secondPass = tryPickPairFrom(groups[groupOrder[retry]], true);
            if (secondPass) pairs.push(secondPass);
        }
        // 第三轮：回退到允许无价差过滤但仍保同组、同页不撞车
        var allGroupKeys = Object.keys(fallbackGroups);
        shuffleInPlace(allGroupKeys, rng);
        for (var f = 0; f < allGroupKeys.length && pairs.length < 3; f += 1) {
            while (pairs.length < 3) {
                var fallbackPick = tryPickPairFrom(fallbackGroups[allGroupKeys[f]], false);
                if (!fallbackPick) break;
                pairs.push(fallbackPick);
            }
        }
        return pairs;
    }

    var visualPoolCache = null;

    // 读取生成的视觉池清单；浏览器走 UMD 全局，Node 走相对 require，双通道同一文件。
    function visualPoolEntries() {
        if (visualPoolCache) return visualPoolCache;
        var manifest = null;
        if (typeof globalThis !== "undefined" && globalThis.BlackMarketVisualPool) {
            manifest = globalThis.BlackMarketVisualPool;
        } else if (environment.commonJs) {
            try {
                manifest = require("../visual/visual-pool-manifest.js");
            } catch (error) {
                manifest = null;
            }
        }
        var entries = manifest && Array.isArray(manifest.entries) ? manifest.entries : [];
        visualPoolCache = entries.filter(function(entry) {
            return entry && typeof entry.u === "string" && /^icons\/[0-9a-f]+_\d+\.webp$/.test(entry.u);
        });
        return visualPoolCache;
    }

    function deterministicHex(label, sequence, byteLength) {
        var out = "";
        var block = 0;
        while (out.length < byteLength * 2) {
            out += (hash32(label + ":" + sequence + ":" + block) + 0x100000000)
                .toString(16).slice(-8);
            block += 1;
        }
        return out.slice(0, byteLength * 2);
    }

    function deterministicBytes(label) {
        var sequence = 0;
        return function(length) {
            sequence += 1;
            var hex = deterministicHex(label, sequence, length);
            var bytes = new Uint8Array(length);
            var index;
            for (index = 0; index < length; index += 1) {
                bytes[index] = parseInt(hex.slice(index * 2, index * 2 + 2), 16);
            }
            return bytes;
        };
    }

    function randomHex(nextBytes, byteLength) {
        var bytes = nextBytes(byteLength);
        invariant(bytes && bytes.length === byteLength, "随机熵源异常");
        var out = "";
        var index;
        for (index = 0; index < bytes.length; index += 1) {
            out += (bytes[index] + 256).toString(16).slice(-2);
        }
        return out;
    }

    function createByteRng(nextBytes) {
        function nextUint32() {
            var bytes = nextBytes(4);
            invariant(bytes && bytes.length === 4, "随机熵源异常");
            return (((bytes[0] << 24) >>> 0) + (bytes[1] << 16)
                + (bytes[2] << 8) + bytes[3]) >>> 0;
        }
        return {
            next: function() {
                return nextUint32() / 4294967296;
            },
            int: function(max) {
                invariant(Number.isInteger(max) && max > 0 && max <= 4294967296,
                    "随机数范围非法");
                var limit = Math.floor(4294967296 / max) * max;
                var value;
                do { value = nextUint32(); } while (value >= limit);
                return value % max;
            }
        };
    }

    function validateOptions(options) {
        var input = options === undefined ? {} : options;
        invariant(isObject(input), "匿名产品参数非法");
        var allowed = { tradePoints: true, kPoints: true, supplyCredits: true, decryptLevel: true, seed: true };
        invariant(Object.keys(input).every(function(key) { return allowed[key] === true; }),
            "anonymous product does not accept an exact directory or unknown fields");
        var opts = {};
        if (input.tradePoints !== undefined) {
            invariant(isSafeNonNegativeInteger(input.tradePoints), "交易点参数非法");
            opts.tradePoints = input.tradePoints;
        }
        if (input.kPoints !== undefined) {
            invariant(isSafeNonNegativeInteger(input.kPoints), "K 点参数非法");
            opts.kPoints = input.kPoints;
        }
        if (input.supplyCredits !== undefined) {
            invariant(isSafeNonNegativeInteger(input.supplyCredits), "补货信用参数非法");
            opts.supplyCredits = input.supplyCredits;
        }
        if (input.decryptLevel !== undefined) {
            invariant(LEVELS.indexOf(input.decryptLevel) >= 0, "解密等级非法");
            opts.decryptLevel = input.decryptLevel;
        }
        return opts;
    }

    function makeProgress() {
        return {
            status: "open",
            selectedOfferId: null,
            payment: null,
            paidAmount: 0,
            revealed: null,
            siblingResidue: null,
            settlement: null
        };
    }

    function spreadBandFor(spreadTp) {
        if (spreadTp >= 25000) return { tier: "large", label: "高波差" };
        if (spreadTp >= 5000) return { tier: "medium", label: "中波差" };
        return { tier: "small", label: "小波差" };
    }

    function decryptHintText(decryptLevel, pair) {
        if (decryptLevel >= 10) return "脱壳净值锁定 · 协议全解";
        if (decryptLevel >= 8) {
            var band = spreadBandFor(pair.spreadTp);
            return "能级" + band.label + " · 方向未明";
        }
        if (decryptLevel >= 6) return "强化石耦合读数 · 表层剥离";
        if (decryptLevel >= 5) return "基础轮廓剥离 · 无色检视";
        if (decryptLevel >= 3) return "破局泄口暴露 · 局部表面";
        if (decryptLevel >= 1) return "纳米壳微退 · 轮廓隐现";
        return "高危蛰伏封壳 · 零解密";
    }

    function createSessionInternal(options, nextBytes) {
        var opts = validateOptions(options);
        var pageNumber = 1;
        var revision = 1;
        var tradePoints = opts.tradePoints === undefined ? 200000 : opts.tradePoints;
        var kPoints = opts.kPoints === undefined ? 2000 : opts.kPoints;
        var supplyCredits = opts.supplyCredits === undefined ? 2 : opts.supplyCredits;
        var rawBoxes = 3;
        var decryptLevel = opts.decryptLevel === undefined ? 3 : opts.decryptLevel;
        var page;
        var progress = {};
        var pending = null;
        var previews = {};
        var receipts = [];
        var history = [];
        var collectionCount = 0;

        function preparePage() {
            var rng = createByteRng(nextBytes);
            var pairs = [];
            var pairIndex;
            var poolEntries = visualPoolEntries();
            var visualPairs = planVisualPairings(rng, poolEntries);

            for (pairIndex = 1; pairIndex <= 3; pairIndex += 1) {
                var pairId = "P" + pageNumber + "-" + pairIndex;
                var visualPair = visualPairs[pairIndex - 1] || null;
                var counterPriceTp;
                var settlementA;
                var settlementB;
                var poolIdxA = -1;
                var poolIdxB = -1;
                var highOnA;

                if (visualPair && visualPair.bounds) {
                    var entryFirst = poolEntries[visualPair.first];
                    var entrySecond = poolEntries[visualPair.second];
                    var firstIsHigher = (Number(entryFirst.s) || 0) >= (Number(entrySecond.s) || 0);
                    var highPoolIdx = firstIsHigher ? visualPair.first : visualPair.second;
                    var lowPoolIdx = firstIsHigher ? visualPair.second : visualPair.first;
                    var highEntry = poolEntries[highPoolIdx];
                    var lowEntry = poolEntries[lowPoolIdx];
                    counterPriceTp = pickCounterPriceFromBounds(visualPair.bounds, rng);
                    highOnA = rng.next() < 0.5;
                    poolIdxA = highOnA ? highPoolIdx : lowPoolIdx;
                    poolIdxB = highOnA ? lowPoolIdx : highPoolIdx;
                    settlementA = highOnA ? highEntry.s : lowEntry.s;
                    settlementB = highOnA ? lowEntry.s : highEntry.s;
                } else {
                    counterPriceTp = PRICE_POINTS[rng.int(PRICE_POINTS.length)];
                    // 回退合成价也保持盲选期望 <= 0（亏损 1–16 档 vs 盈利 1–12 档）
                    var lowSettlementTp = Math.max(50, counterPriceTp - (1 + rng.int(16)) * TP_PER_K);
                    var highSettlementTp = counterPriceTp + (1 + rng.int(12)) * TP_PER_K;
                    highOnA = rng.next() < 0.5;
                    settlementA = highOnA ? highSettlementTp : lowSettlementTp;
                    settlementB = highOnA ? lowSettlementTp : highSettlementTp;
                    if (visualPair) {
                        poolIdxA = highOnA ? visualPair.first : visualPair.second;
                        poolIdxB = highOnA ? visualPair.second : visualPair.first;
                    }
                }

                var handleA = "opaque-visual-" + randomHex(nextBytes, 20);
                var handleB = "opaque-visual-" + randomHex(nextBytes, 20);
                var seedA = randomHex(nextBytes, 16);
                var seedB = randomHex(nextBytes, 16);
                var spreadTp = Math.abs(settlementA - settlementB);

                function makeOffer(side, high, handle, surfaceSeed, settlementTp, poolIdx) {
                    return {
                        offerId: pairId + "-" + side,
                        side: side,
                        visualHandle: handle,
                        settlementTp: settlementTp,
                        syntheticTier: high ? "high" : "low",
                        surfaceSeed: surfaceSeed,
                        visualPool: poolIdx
                    };
                }

                pairs.push({
                    pairId: pairId,
                    index: pairIndex,
                    category: "anonymous",
                    subclass: "匿名影子货舱",
                    counterPriceTp: counterPriceTp,
                    kCost: Math.ceil(counterPriceTp / TP_PER_K),
                    spreadTp: spreadTp,
                    similarityMode: "anonymous-synthetic",
                    coverageParity: {
                        metric: "object-alpha-pixels",
                        anchorMode: "automatic-pca-skeleton",
                        orientationMode: "automatic-orthogonal",
                        maxCoverageDelta: 0.002
                    },
                    offers: [
                        makeOffer("A", highOnA, handleA, seedA, settlementA, poolIdxA),
                        makeOffer("B", !highOnA, handleB, seedB, settlementB, poolIdxB)
                    ]
                });
            }
            return {
                pageId: "opaque-page-" + randomHex(nextBytes, 16),
                pageNumber: pageNumber,
                pairs: pairs
            };
        }

        function resetProgress() {
            progress = {};
            page.pairs.forEach(function(pair) { progress[pair.pairId] = makeProgress(); });
            pending = null;
            previews = {};
        }

        function bump() {
            revision += 1;
            previews = {};
        }

        function currentPair(pairId) {
            var pair = page.pairs.filter(function(candidate) { return candidate.pairId === pairId; })[0];
            invariant(!!pair, "目标货舱不在当前批次内");
            return pair;
        }

        function currentOffer(pair, offerId) {
            var offer = pair.offers.filter(function(candidate) { return candidate.offerId === offerId; })[0];
            invariant(!!offer, "目标货包不在所选货舱内");
            return offer;
        }

        function currentOfferByHandle(visualHandle) {
            invariant(isSafeString(visualHandle, 128), "视觉句柄非法");
            var pairIndex;
            var offerIndex;
            for (pairIndex = 0; pairIndex < page.pairs.length; pairIndex += 1) {
                for (offerIndex = 0; offerIndex < page.pairs[pairIndex].offers.length; offerIndex += 1) {
                    if (page.pairs[pairIndex].offers[offerIndex].visualHandle === visualHandle) {
                        return page.pairs[pairIndex].offers[offerIndex];
                    }
                }
            }
            invariant(false, "视觉句柄不在当前批次内");
            return null;
        }

        function callKey(operation, callId) {
            invariant(isSafeString(callId, 128), "请求编号非法");
            return operation + ":" + callId;
        }

        function requestDigest(request) {
            return JSON.stringify(request || {});
        }

        function replay(operation, callId, request) {
            var key = callKey(operation, callId);
            var found = receipts.filter(function(receipt) { return receipt.key === key; })[0];
            if (found) {
                invariant(found.requestDigest === requestDigest(request), "callId reused with different request");
            }
            return found ? clone(found.snapshot) : null;
        }

        function record(operation, callId, request, value) {
            var key = callKey(operation, callId);
            receipts = receipts.filter(function(receipt) { return receipt.key !== key; });
            receipts.push({ key: key, requestDigest: requestDigest(request), snapshot: clone(value) });
            if (receipts.length > MAX_RECEIPTS) receipts.splice(0, receipts.length - MAX_RECEIPTS);
        }

        function isComplete() {
            return page.pairs.every(function(pair) {
                var status = progress[pair.pairId].status;
                return status !== "open" && status !== "pending";
            });
        }

        function resolvePoolEntryFor(offer) {
            var poolEntries = visualPoolEntries();
            if (typeof offer.visualPool !== "number" || offer.visualPool < 0 || !poolEntries.length) {
                return null;
            }
            return poolEntries[offer.visualPool % poolEntries.length] || null;
        }

        function buildPageSummary() {
            var pageRows = history.filter(function(row) {
                return row.pageNumber === pageNumber
                    && (row.terminal === "extracted" || row.terminal === "resold" || row.terminal === "skipped");
            });
            var wins = 0;
            var purchases = 0;
            var skips = 0;
            var extracted = 0;
            var pageDeltaV = 0;
            for (var i = 0; i < pageRows.length; i += 1) {
                var row = pageRows[i];
                if (row.terminal === "skipped") {
                    skips += 1;
                } else {
                    purchases += 1;
                    if (row.wasWinner) wins += 1;
                    if (row.terminal === "extracted") extracted += 1;
                    pageDeltaV += row.deltaV;
                }
            }
            var sessionDeltaV = 0;
            for (var j = 0; j < history.length; j += 1) {
                sessionDeltaV += history[j].deltaV;
            }
            return {
                wins: wins,
                purchases: purchases,
                skips: skips,
                extracted: extracted,
                pageDeltaV: pageDeltaV,
                sessionDeltaV: sessionDeltaV
            };
        }

        function projectOffer(pair, offer) {
            var state = progress[pair.pairId];
            var chosen = state.selectedOfferId === offer.offerId;
            var terminal = state.status === "extracted" || state.status === "resold";
            var visualState = "available";
            if (state.status === "skipped") visualState = "sealed";
            else if ((state.status === "pending" || terminal) && chosen) visualState = "revealed";
            else if ((state.status === "pending" || terminal) && !chosen) visualState = "withdrawn";
            return {
                offerId: offer.offerId,
                side: offer.side,
                quantity: 1,
                category: pair.category,
                subclass: pair.subclass,
                visualHandle: offer.visualHandle,
                presentationKind: "sealed-abstract",
                label: "未脱壳封件 " + offer.side,
                hint: decryptHintText(decryptLevel, pair),
                spreadBand: decryptLevel >= 8 && decryptLevel < 10 && state.status === "open"
                    ? spreadBandFor(pair.spreadTp) : null,
                direction: decryptLevel >= 10 && state.status === "open"
                    ? (offer.settlementTp > pair.counterPriceTp ? "profit" : "loss") : null,
                visualState: visualState,
                surface: {
                    algorithmVersion: ALGORITHM_VERSION,
                    targetCoverage: COVERAGE_BY_LEVEL[decryptLevel],
                    coverageMetric: "object-alpha-pixels",
                    anchorMode: "automatic-pca-skeleton",
                    orientationMode: "automatic-orthogonal"
                },
                revealed: chosen && state.revealed ? clone(state.revealed) : null
            };
        }

        function snapshot() {
            var openPairs = page.pairs.filter(function(pair) {
                return progress[pair.pairId].status === "open";
            }).length;
            return {
                schemaVersion: SNAPSHOT_SCHEMA,
                revision: revision,
                shadowOnly: true,
                fixtureOnly: true,
                productionWrites: false,
                identityBoundary: IDENTITY_BOUNDARY,
                algorithmVersion: ALGORITHM_VERSION,
                catalog: {
                    kind: "anonymous-synthetic",
                    digest: FIXTURE_DIGEST,
                    totalItems: 6,
                    mechanicallyRenderable: 6,
                    mechanicallyRejected: 0,
                    byCategory: { anonymous: 6 }
                },
                balances: {
                    tradePoints: tradePoints,
                    kPoints: kPoints,
                    supplyCredits: supplyCredits,
                    rawBoxes: rawBoxes
                },
                decryptLevel: decryptLevel,
                mudCoverage: COVERAGE_BY_LEVEL[decryptLevel],
                page: {
                    id: page.pageId,
                    number: pageNumber,
                    complete: isComplete(),
                    openPairs: openPairs
                },
                pairs: page.pairs.map(function(pair) {
                    var state = progress[pair.pairId];
                    var terminalSettled = state.status === "extracted" || state.status === "resold";
                    return {
                        pairId: pair.pairId,
                        index: pair.index,
                        category: pair.category,
                        subclass: pair.subclass,
                        counterPriceTp: pair.counterPriceTp,
                        kCost: pair.kCost,
                        status: state.status,
                        similarityMode: pair.similarityMode,
                        spreadBand: decryptLevel >= 8 && state.status === "open"
                            ? spreadBandFor(pair.spreadTp) : null,
                        siblingResidue: terminalSettled && state.siblingResidue
                            ? clone(state.siblingResidue) : null,
                        coverageParity: {
                            metric: pair.coverageParity.metric,
                            anchorMode: pair.coverageParity.anchorMode,
                            orientationMode: pair.coverageParity.orientationMode,
                            maxCoverageDelta: pair.coverageParity.maxCoverageDelta,
                            targetCoverage: COVERAGE_BY_LEVEL[decryptLevel]
                        },
                        offers: pair.offers.map(function(offer) { return projectOffer(pair, offer); })
                    };
                }),
                pending: pending ? clone(pending) : null,
                collectionCount: collectionCount,
                historyCount: history.length,
                summary: buildPageSummary()
            };
        }

        page = preparePage();
        resetProgress();

        var productPort = {
            open: function() { return snapshot(); },
            purchasePreview: function(intent) {
                invariant(isObject(intent), "购买请求格式非法");
                invariant(pending === null, "先结清已脱壳的货物");
                invariant(intent.payment === "tp" || intent.payment === "k", "不支持的支付方式");
                var pair = currentPair(intent.pairId);
                invariant(progress[pair.pairId].status === "open", "该货舱已完成结算或封存");
                currentOffer(pair, intent.offerId);
                var cost = intent.payment === "tp" ? pair.counterPriceTp : pair.kCost;
                invariant(intent.payment !== "tp" || tradePoints >= cost, "交易点不足，可先上交毛坯盲盒换取工钱");
                invariant(intent.payment !== "k" || kPoints >= cost, "K 点不足，可改用交易点或按 50:1 兑换");
                var token = "pv-" + revision + "-" + pair.pairId + "-" + intent.offerId + "-" + intent.payment;
                var result = {
                    token: token,
                    revision: revision,
                    pairId: pair.pairId,
                    offerId: intent.offerId,
                    payment: intent.payment,
                    cost: cost
                };
                previews[token] = result;
                return clone(result);
            },
            purchaseCommit: function(token, callId) {
                var request = { token: token };
                var prior = replay("purchaseCommit", callId, request);
                if (prior) return prior;
                invariant(pending === null, "先结清已脱壳的货物");
                var preview = previews[token];
                invariant(!!preview && preview.revision === revision, "报价预览已过期，请重新选中货包");
                var pair = currentPair(preview.pairId);
                var offer = currentOffer(pair, preview.offerId);
                invariant(progress[pair.pairId].status === "open", "该货舱已完成结算或封存");
                if (preview.payment === "tp") {
                    invariant(tradePoints >= preview.cost, "交易点不足");
                    tradePoints -= preview.cost;
                } else {
                    invariant(kPoints >= preview.cost, "K 点不足");
                    kPoints -= preview.cost;
                }
                var valueDelta = offer.settlementTp
                    - (preview.payment === "tp" ? preview.cost : preview.cost * TP_PER_K);
                var poolEntry = resolvePoolEntryFor(offer);
                var releasable = poolEntry && poolEntry.e !== "banned";
                progress[pair.pairId] = {
                    status: "pending",
                    selectedOfferId: offer.offerId,
                    payment: preview.payment,
                    paidAmount: preview.cost,
                    revealed: {
                        displayName: releasable ? poolEntry.n
                            : "匿名影子货物 · " + (offer.syntheticTier === "high" ? "高值" : "低值"),
                        quantity: 1,
                        basePrice: releasable ? poolEntry.p : offer.settlementTp * 4,
                        resellValue: offer.settlementTp,
                        payment: preview.payment,
                        paidAmount: preview.cost,
                        deltaTp: offer.settlementTp - (preview.payment === "tp" ? preview.cost : 0),
                        deltaK: preview.payment === "k" ? -preview.cost : 0,
                        deltaV: valueDelta,
                        direction: valueDelta > 0 ? "profit" : "loss",
                        wasWinner: valueDelta > 0,
                        realInfo: releasable ? {
                            name: poolEntry.n,
                            type: poolEntry.t,
                            subclass: poolEntry.sc,
                            catalogPrice: poolEntry.p,
                            saleValue: poolEntry.s,
                            actionType: poolEntry.at
                        } : null
                    },
                    siblingResidue: null,
                    settlement: null
                };
                pending = { pairId: pair.pairId, offerId: offer.offerId, commitCallId: callId };
                bump();
                var committed = snapshot();
                record("purchaseCommit", callId, request, committed);
                return committed;
            },
            settle: function(action, callId) {
                var request = { action: action };
                var prior = replay("settle", callId, request);
                if (prior) return prior;
                invariant(action === "extract" || action === "resell", "结算方式非法");
                invariant(!!pending, "当前没有待结算的脱壳货物");
                var pairId = pending.pairId;
                var pair = currentPair(pairId);
                var state = progress[pairId];
                invariant(state.status === "pending" && !!state.revealed, "待结算状态异常");
                if (action === "resell") tradePoints += state.revealed.resellValue;
                else collectionCount += 1;
                state.status = action === "resell" ? "resold" : "extracted";
                state.settlement = action;

                // 单组终局后释放被牺牲为纳米炸弹的兄弟件残片读数（反事实复盘学习，购买前零泄密）
                var siblingOffer = pair.offers.filter(function(candidate) {
                    return candidate.offerId !== state.selectedOfferId;
                })[0];
                if (siblingOffer) {
                    var siblingPool = resolvePoolEntryFor(siblingOffer);
                    var siblingReleasable = siblingPool && siblingPool.e !== "banned";
                    var siblingDeltaV = siblingOffer.settlementTp - pair.counterPriceTp;
                    state.siblingResidue = {
                        side: siblingOffer.side,
                        displayName: siblingReleasable ? siblingPool.n
                            : "未收录黑货（" + (siblingOffer.syntheticTier === "high" ? "高值" : "低值") + "）",
                        catalogPrice: siblingReleasable ? siblingPool.p : siblingOffer.settlementTp * 4,
                        saleValue: siblingOffer.settlementTp,
                        wasWinner: siblingDeltaV > 0,
                        deltaV: siblingDeltaV
                    };
                }

                var deltaTp = state.payment === "tp" ? -state.paidAmount : 0;
                var deltaK = state.payment === "k" ? -state.paidAmount : 0;
                if (action === "resell") deltaTp += state.revealed.resellValue;
                history.push({
                    pageNumber: pageNumber,
                    pairId: pairId,
                    side: state.selectedOfferId.slice(-1),
                    wasWinner: state.revealed.wasWinner,
                    payment: state.payment,
                    deltaTp: deltaTp,
                    deltaK: deltaK,
                    deltaV: deltaTp + deltaK * TP_PER_K,
                    terminal: state.status
                });
                pending = null;
                bump();
                var settled = snapshot();
                record("settle", callId, request, settled);
                return settled;
            },
            skip: function(pairId, callId) {
                var request = { pairId: pairId };
                var prior = replay("skip", callId, request);
                if (prior) return prior;
                invariant(pending === null, "先结清已脱壳的货物");
                var pair = currentPair(pairId);
                invariant(progress[pair.pairId].status === "open", "该货舱已完成结算或封存");
                progress[pair.pairId].status = "skipped";
                history.push({
                    pageNumber: pageNumber,
                    pairId: pairId,
                    side: null,
                    wasWinner: null,
                    payment: null,
                    deltaTp: 0,
                    deltaK: 0,
                    deltaV: 0,
                    terminal: "skipped"
                });
                bump();
                var skipped = snapshot();
                record("skip", callId, request, skipped);
                return skipped;
            },
            nextPage: function(callId) {
                var request = {};
                var prior = replay("nextPage", callId, request);
                if (prior) return prior;
                invariant(pending === null, "先结清已脱壳的货物");
                invariant(isComplete(), "当前批次还有未处理的货舱");
                invariant(supplyCredits > 0, "补货信用不足，可先上交毛坯盲盒获取信用");
                supplyCredits -= 1;
                pageNumber += 1;
                page = preparePage();
                resetProgress();
                bump();
                var next = snapshot();
                record("nextPage", callId, request, next);
                return next;
            },
            // 保底正收益轨道：将战斗获取的未清洗毛坯直接卖给假肢仙人（零风险固定 TP + 补货信用）
            redeemRawBox: function(callId) {
                var request = { kind: "rawbox" };
                var prior = replay("redeemRawBox", callId, request);
                if (prior) return prior;
                invariant(pending === null, "先结清已脱壳的货物");
                invariant(rawBoxes > 0, "手头已没有未清洗毛坯盲盒");
                rawBoxes -= 1;
                tradePoints += RAW_BOX_REDEEM_TP;
                supplyCredits += 1;
                history.push({
                    pageNumber: pageNumber,
                    pairId: null,
                    side: null,
                    wasWinner: null,
                    payment: null,
                    deltaTp: RAW_BOX_REDEEM_TP,
                    deltaK: 0,
                    deltaV: RAW_BOX_REDEEM_TP,
                    terminal: "rawbox"
                });
                bump();
                var redeemed = snapshot();
                record("redeemRawBox", callId, request, redeemed);
                return redeemed;
            },
            // 50 TP -> 1 K 单向整额兑换（ΔV = 0，余数保留）
            redeemK: function(kAmount, callId) {
                var request = { kAmount: kAmount };
                var prior = replay("redeemK", callId, request);
                if (prior) return prior;
                invariant(pending === null, "先结清已脱壳的货物");
                invariant(isSafePositiveInteger(kAmount), "兑换 K 点数量必须为正整数");
                var costTp = kAmount * TP_PER_K;
                invariant(tradePoints >= costTp, "交易点不足，无法兑换 " + kAmount + " K");
                tradePoints -= costTp;
                kPoints += kAmount;
                history.push({
                    pageNumber: pageNumber,
                    pairId: null,
                    side: null,
                    wasWinner: null,
                    payment: "tp",
                    deltaTp: -costTp,
                    deltaK: kAmount,
                    deltaV: 0,
                    terminal: "redeem_k"
                });
                bump();
                var exchanged = snapshot();
                record("redeemK", callId, request, exchanged);
                return exchanged;
            }
        };

        var surfacePort = {
            resolveSurface: function(visualHandle) {
                var offer = currentOfferByHandle(visualHandle);
                var poolEntries = visualPoolEntries();
                if (!poolEntries.length || typeof offer.visualPool !== "number" || offer.visualPool < 0) {
                    return {
                        kind: "sealed-abstract",
                        assetUrl: SAFE_SURFACE_DATA_URL,
                        sourceKey: "sealed-abstract-surface.v1",
                        sourceKind: "sealed-abstract",
                        sourceComposition: "identity-independent-safe-surface",
                        previewGender: "neutral",
                        seed: offer.surfaceSeed,
                        autoRotate: false,
                        sharpenSource: false,
                        sourceMaskMode: "source",
                        hiddenColorMode: HIDDEN_COLOR_MODE
                    };
                }
                var poolEntry = poolEntries[offer.visualPool % poolEntries.length];
                return {
                    kind: "sealed-abstract",
                    assetUrl: poolEntry.u,
                    fallbackAssetUrl: poolEntry.f || null,
                    fallbackHiddenColorMode: "monochrome",
                    fallbackSourceMaskMode: poolEntry.fm || "monochrome",
                    sourceKey: "anonymous-visual-pool.v2#" + (offer.visualPool % poolEntries.length),
                    sourceKind: "icon",
                    sourceComposition: "anonymous-visual-pool",
                    previewGender: "neutral",
                    seed: offer.surfaceSeed,
                    autoRotate: true,
                    sharpenSource: true,
                    sourceMaskMode: poolEntry.h || "proxy",
                    hiddenColorMode: HIDDEN_COLOR_MODE
                };
            }
        };

        var auditPort = {
            exportAnonymous: function() {
                return {
                    schemaVersion: "black-market-anonymous-shadow-export.v2",
                    shadowOnly: true,
                    identityBoundary: IDENTITY_BOUNDARY,
                    pageNumber: pageNumber,
                    decryptLevel: decryptLevel,
                    balances: {
                        tradePoints: tradePoints,
                        kPoints: kPoints,
                        supplyCredits: supplyCredits,
                        rawBoxes: rawBoxes
                    },
                    history: clone(history)
                };
            }
        };

        return { product: productPort, surface: surfacePort, audit: auditPort };
    }

    function createShadowSession(options) {
        return createSessionInternal(options, environment.randomBytes);
    }

    function createTestProductSession(options, entropyLabel) {
        invariant(environment.commonJs, "test entropy seam is not available in the browser product core");
        invariant(isSafeString(entropyLabel, 160), "test entropy label invalid");
        return createSessionInternal(options, deterministicBytes("test-private-" + entropyLabel));
    }

    var exports = {
        SNAPSHOT_SCHEMA: SNAPSHOT_SCHEMA,
        ALGORITHM_VERSION: ALGORITHM_VERSION,
        HIDDEN_COLOR_MODE: HIDDEN_COLOR_MODE,
        IDENTITY_BOUNDARY: IDENTITY_BOUNDARY,
        RAW_BOX_REDEEM_TP: RAW_BOX_REDEEM_TP,
        TP_PER_K: TP_PER_K,
        LEVELS: LEVELS.slice(),
        COVERAGE_BY_LEVEL: clone(COVERAGE_BY_LEVEL),
        createShadowSession: createShadowSession,
        hash32: hash32
    };
    if (environment.commonJs) exports.createTestProductSession = createTestProductSession;
    return exports;
});
